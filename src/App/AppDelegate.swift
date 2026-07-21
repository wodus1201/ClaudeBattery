import Cocoa
import ServiceManagement

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var last: UsageResult = UsageResult()
    var backoff: TimeInterval = 0   // grows on 429, resets on success
    var sleeping = false            // rate-limited (429): show dozing widget
    var isMocking = false           // UI-testing mode: never schedule a real fetch

    // Animation + live-render state
    var animTimer: Timer?
    var animTick: Int = 0
    var cycleStart = Date()          // anchors the text-slot swap cycle
    var driverUsed: Int? = nil       // used% of the tracked limit
    var driverResets: Date? = nil
    var lastLimits: [Limit] = []     // limits from the latest successful fetch
    // Which limit the widget tracks. Default = 5-hour session; user can switch
    // from the click menu, and the choice persists across restarts.
    var selectedKind: String = UserDefaults.standard.string(forKey: "selectedKind") ?? "session"
    // Compact mode: hides "Lv--" and shrinks the dialogue slot, so the widget
    // fits menu bars with limited space (e.g. MacBook Pro w/ many other icons)
    // instead of being pushed into the ">>" overflow. Default ON; togglable
    // from the click menu; persists across restarts.
    var compact: Bool = UserDefaults.standard.object(forKey: "compact") as? Bool ?? true
    // Chosen Claude skin (color). Applies to both the widget and the battle
    // screen; persists across restarts. The shiny is gated behind petCount.
    var selectedSkinID: String = UserDefaults.standard.string(forKey: "clawdSkin") ?? "default"
    var petCount: Int = UserDefaults.standard.integer(forKey: "petCount")
    var currentSkin: ClawdSkin { skin(id: selectedSkinID) }
    /// A skin is pickable if it has no unlock gate or the gate is met.
    func isUnlocked(_ s: ClawdSkin) -> Bool { petCount >= s.unlockPets }
    var hasData = false
    var lastSignature = ""

    // Sprite-click ("petting") interaction. The status item has no attached menu
    // — the button action routes clicks by x-position — so we stash the menu the
    // button should pop up when the click lands outside the sprite.
    var currentMenu: NSMenu?
    var pettingUntil: Date?          // non-nil while the happy face + line show
    var pettingLine: String = ""
    var lastPettingLine: String = "" // avoid repeating a line back-to-back
    /// Sprite hit box in button coordinates, recorded at draw time.
    var spriteHitMaxX: CGFloat = 0

    // Self-update state
    var updateTimer: Timer?
    var availableUpdate: Release?    // non-nil once a newer release is seen
    var isUpdating = false           // guards against a double-click on 업데이트

    // Battle screen: the drop-down panel a left-click opens.
    var battlePanel: BattlePanel?
    var battleMonitor: Any?          // dismisses the panel on a click elsewhere
    var battleClosedAt: Date?        // when the panel last closed, so a status-item
                                     // click that both dismissed AND re-triggered
                                     // buttonClicked doesn't immediately reopen it

    // Text-slot timing (seconds)
    let TIME_HOLD = 5.0             // how long the reset-countdown shows
    let FLAVOR_HOLD = 5.0            // how long the flavor line shows
    let CROSSFADE = 0.45            // swap transition duration

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerPixelFont()

        // Debug: CLAUDEMONSTER_DUMP=<path> renders sample frames and exits.
        if let dump = ProcessInfo.processInfo.environment["CLAUDEMONSTER_DUMP"] {
            dumpSamples(to: dump); exit(0)
        }
        // Debug: CLAUDEMONSTER_BATTLE=<path> renders the battle panel and exits.
        // Lets the drop-down's design be checked without a window or a network call.
        if let path = ProcessInfo.processInfo.environment["CLAUDEMONSTER_BATTLE"] {
            let pct = Int(ProcessInfo.processInfo.environment["CLAUDEMONSTER_MOCK_PERCENT"] ?? "") ?? 16
            dumpBattle(to: path, usedPercent: pct); exit(0)
        }
        // Build hook: CLAUDEMONSTER_ICON=<path> renders the 1024px app icon and exits.
        // make-icon.sh calls this, so the icon always matches the live sprite.
        if let icon = ProcessInfo.processInfo.environment["CLAUDEMONSTER_ICON"] {
            writeIconPNG(to: icon); exit(0)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // No statusItem.menu: we handle clicks ourselves so a click on the sprite
        // can pet Claude instead of opening the menu. See buttonClicked().
        if let b = statusItem.button {
            b.target = self
            b.action = #selector(buttonClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        setTitle(text: " 클로드 …", color: .secondaryLabelColor)
        // ~12fps animation loop; renderNow() is a no-op cheap-skip when nothing changed.
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.animTick += 1
            self?.renderNow()
        }

        // UI testing without hitting the network at all: CLAUDEMONSTER_MOCK=1
        // feeds fake usage data straight in and never calls fetchUsage/refresh.
        // Optional CLAUDEMONSTER_MOCK_PERCENT=NN overrides the session used%.
        if ProcessInfo.processInfo.environment["CLAUDEMONSTER_MOCK"] != nil {
            isMocking = true
            applyMock()
            return
        }
        migrateLegacyPreferences()
        retireLegacyInstall()
        refresh()
        scheduleUpdateChecks()

        // After the widget is actually on screen, so "메뉴바에 나타났습니다" is true.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.showWelcomeIfFirstRun()
        }
    }

    func applyMock() {
        let env = ProcessInfo.processInfo.environment
        let sessionPct = Int(env["CLAUDEMONSTER_MOCK_PERCENT"] ?? "") ?? 41
        let now = Date()
        var mock = UsageResult()
        mock.limits = [
            Limit(kind: "session", percent: sessionPct,
                  resetsAt: now.addingTimeInterval(3600 * 2 + 60 * 13), scopeName: nil, isActive: false),
            Limit(kind: "weekly_all", percent: 55,
                  resetsAt: now.addingTimeInterval(3600 * 24 * 3), scopeName: nil, isActive: true),
            // Mirrors what the API actually returns for an untouched scoped limit:
            // nothing used, so its weekly window never opened and resets_at is null.
            // That's the case the "포켓몬센터 도착!" line exists for — keep it here
            // so mock mode can still reach it.
            Limit(kind: "weekly_scoped", percent: 0,
                  resetsAt: nil, scopeName: "Fable", isActive: false),
        ]
        apply(mock)
        // No real fetch loop is running, so nothing will call apply() again —
        // that's the point: no more network calls while you eyeball the UI.
    }

    /// Self-scheduling loop: normal cadence, but back off exponentially on 429
    /// so we never hammer the usage endpoint into a longer block.
    func scheduleNext() {
        let delay: TimeInterval
        if backoff > 0 {
            delay = min(backoff, MAX_BACKOFF)
        } else {
            delay = REFRESH_SECONDS
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    func setTitle(text: String, color: NSColor) {
        statusItem.button?.image = nil          // clear any drawn image
        let attr = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.foregroundColor, value: color, range: range)
        attr.addAttribute(.font,
                          value: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                          range: range)
        statusItem.button?.attributedTitle = attr
    }

    /// Decide what the dialogue slot shows: the reset countdown by default,
    /// briefly swapping to a flavor line, with a crossfade at each boundary.
    /// Returns (incoming, outgoing?, alpha 0..1 for incoming).
    func slotTexts(elapsed: TimeInterval, remaining: Int) -> (String, String?, CGFloat) {
        let timeText = resetKorean(driverResets)
        let flavorText = flavorLine(remaining: remaining)
        let period = TIME_HOLD + FLAVOR_HOLD
        let ph = elapsed.truncatingRemainder(dividingBy: period)

        if ph < CROSSFADE {                                   // boundary → time
            return (timeText, flavorText, CGFloat(ph / CROSSFADE))
        } else if ph >= TIME_HOLD && ph < TIME_HOLD + CROSSFADE {  // boundary → flavor
            return (flavorText, timeText, CGFloat((ph - TIME_HOLD) / CROSSFADE))
        } else if ph < TIME_HOLD {
            return (timeText, nil, 1)
        } else {
            return (flavorText, nil, 1)
        }
    }

    /// Called ~12fps by the animation timer. Cheap-skips when nothing visible
    /// changed, so idle CPU stays near zero.
    func renderNow() {
        // Render whenever we have data OR we're dozing (even with no data yet).
        guard hasData || sleeping else { return }
        // Placeholder HP when we're dozing without ever having fetched data.
        let hpUnknown = (driverUsed == nil)
        let used = driverUsed ?? 0
        let remaining = max(0, min(100, 100 - used))

        let isFainted = !hpUnknown && remaining == 0

        // Petting expires on its own; clear it so the normal cycle resumes.
        if let until = pettingUntil, Date() >= until { pettingUntil = nil }
        let petting = pettingUntil != nil

        let bob = isFainted ? 0 : (animTick / 6) % 2
        let phase = animTick % 24
        var blink = isFainted ? false : (phase == 0 || phase == 1)

        // The shiny twinkles in the menu bar every WIDGET_SPARKLE_PERIOD ticks, so
        // its rarity shows even when no panel is open. A fainted Claude does not
        // sparkle — the joke lands badly at 0 HP.
        // Quantized to a frame index (not a continuous alpha) because it has to go
        // into lastSignature, and a float there would defeat the cheap-skip.
        var sparkleFrame = -1
        if currentSkin.isRare && !isFainted && !sleeping {
            let p = animTick % WIDGET_SPARKLE_PERIOD
            if p < WIDGET_SPARKLE_FRAMES { sparkleFrame = p }
        }

        let primary: String, secondary: String?, alpha: CGFloat
        if sleeping {
            // Dozing: closed eyes, no swap — just the sleep line.
            blink = true
            primary = SLEEP_MESSAGE; secondary = nil; alpha = 1
        } else if petting {
            // Petting: hold the reaction line steady, and never blink away the smile.
            blink = false
            primary = pettingLine; secondary = nil; alpha = 1
        } else {
            let elapsed = Date().timeIntervalSince(cycleStart)
            (primary, secondary, alpha) = slotTexts(elapsed: elapsed, remaining: remaining)
        }

        // skin and sparkleFrame are part of what's on screen, so they belong in the
        // signature — leave either out and the widget keeps the stale image.
        let sig = "\(used)|\(hpUnknown)|\(bob)|\(blink)|sleep=\(sleeping)|pet=\(petting)|\(compact)|\(primary)|\(secondary ?? "")|\(Int(alpha * 12))|\(selectedSkinID)|spk=\(sparkleFrame)"
        if sig == lastSignature { return }
        lastSignature = sig

        let img = buildImage(used: used, remaining: remaining, bob: CGFloat(bob),
                             blink: blink, primary: primary, secondary: secondary, alpha: alpha,
                             sleeping: sleeping, hpUnknown: hpUnknown, compact: compact,
                             petting: petting, sparkleFrame: sparkleFrame)
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.image = img
        statusItem.button?.imagePosition = .imageOnly
    }

    func buildImage(used: Int, remaining: Int, bob: CGFloat, blink: Bool,
                    primary: String, secondary: String?, alpha: CGFloat,
                    sleeping: Bool = false, hpUnknown: Bool = false, compact: Bool = false,
                    petting: Bool = false, sparkleFrame: Int = -1) -> NSImage {
        // When HP is unknown (dozing before any data), the gauge is empty gray.
        let frac: CGFloat = hpUnknown ? 1 : CGFloat(remaining) / 100.0
        // Gauge turns gray while dozing.
        let hpColor = sleeping ? NSColor.systemGray : color(remaining: Double(frac))
        let black = NSColor.black

        let name = "클로드"
        let lv = hpUnknown ? ":Lv--" : ":Lv\(used)"
        let hpLabel = "HP:"
        let hpText = hpUnknown ? "--/100" : "\(remaining)/100"

        // Compact mode shrinks the name too — on a 14" menu bar every point counts.
        let nameAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(compact ? 12 : 15), .foregroundColor: black]
        let lvAttr: [NSAttributedString.Key: Any]   = [.font: pixelFont(12), .foregroundColor: black]
        let hpTextAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(13), .foregroundColor: black]
        let hpLabelAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(10), .foregroundColor: NSColor.systemYellow]
        // Compact mode shrinks the dialogue-slot font so long sentences take less room.
        let slotFont = pixelFont(compact ? 9 : 12)

        let nameSize = (name as NSString).size(withAttributes: nameAttr)
        // Compact mode hides "Lv--" entirely (zero width) to save space.
        let lvSize = compact ? .zero : (lv as NSString).size(withAttributes: lvAttr)
        let hpTextSize = (hpText as NSString).size(withAttributes: hpTextAttr)
        let hpLabelSize = (hpLabel as NSString).size(withAttributes: hpLabelAttr)

        // Fixed slot width = widest string the slot can EVER show, so the whole
        // widget never reflows when text swaps or the countdown ticks. Text is
        // centered within this reserved area.
        let slotAttr: [NSAttributedString.Key: Any] = [.font: slotFont, .foregroundColor: black]
        var slotStrings = allSlotStrings()
        if sleeping { slotStrings.append(SLEEP_MESSAGE) }   // reserve room for the sleep line
        let slotW = ceil(slotStrings.map { ($0 as NSString).size(withAttributes: slotAttr).width }.max() ?? 120)

        // Sprite geometry
        let spriteCols: CGFloat = 20
        let spriteRows: CGFloat = 14
        let cell: CGFloat = 1.28
        let spriteW = spriteCols * cell
        let spriteH = spriteRows * cell

        let hpUnitW = hpLabelSize.width + 8 + 54     // label part + gauge part
        let gaugePartW: CGFloat = 54
        let unitH: CGFloat = 13
        // Compact mode tightens the spacing to match its smaller text — at 9pt the
        // roomier gaps read as gaps, not breathing room.
        let padX: CGFloat = compact ? 5 : 7
        let gap: CGFloat = compact ? 4 : 5
        let spriteNameGap: CGFloat = compact ? 5 : 7   // 스프라이트 ↔ 이름 간격 (이 숫자를 키우면 더 벌어짐)
        let flavorGap: CGFloat = compact ? 7 : 10
        let height = NSStatusBar.system.thickness

        let lvBlockW = compact ? 0 : lvSize.width + gap   // Lv text + its trailing gap, omitted when compact
        let contentW = spriteW + spriteNameGap + nameSize.width + gap + lvBlockW
            + hpUnitW + gap + hpTextSize.width + flavorGap + slotW
        let totalW = ceil(contentW + padX * 2)
        // Sprite occupies [padX, padX + spriteW] horizontally; remember its right
        // edge so buttonClicked() can tell a pet from a menu click.
        spriteHitMaxX = padX + spriteW

        let img = NSImage(size: NSSize(width: totalW, height: height), flipped: false) { rect in
            // Off-white rounded background pill.
            NSColor(white: 0.90, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 5, yRadius: 5).fill()

            let midY = rect.midY
            var x = padX

            // Sprite (left of the name), with a subtle vertical bob.
            // Unknown HP (dozing pre-data) uses the healthy face so blink = closed eyes.
            // Petting smiles — unless Claude has fainted, who stays fainted.
            var mood = hpUnknown ? .healthy : mood(remaining: remaining)
            if petting && mood != .fainted { mood = .happy }
            let frames = spriteGrids[mood] ?? spriteGrids[.healthy]!
            let grid = (blink && frames.count > 1) ? frames[1] : frames[0]
            let spriteOrigin = NSPoint(x: x, y: midY - spriteH / 2 + bob)
            // Fainted stays grayscale regardless of skin; otherwise use the skin.
            let colors: [Character: NSColor] = remaining == 0 ? spriteColorsFainted : self.currentSkin.widgetColors
            drawSprite(grid, origin: spriteOrigin, cell: cell, colors: colors)

            // The shiny's periodic twinkle. Drawn inside the sprite's own box so it
            // cannot widen the widget — the menu bar gives us 22px and no more.
            if sparkleFrame >= 0 {
                let t = Double(sparkleFrame) / Double(WIDGET_SPARKLE_FRAMES)
                drawSparkles(in: NSRect(x: spriteOrigin.x, y: spriteOrigin.y,
                                        width: spriteW, height: spriteH),
                             t: t, gold: SHINY_GOLD)
            }
            x += spriteW + spriteNameGap   // 스프라이트 ↔ 이름 간격

            func drawText(_ s: String, _ attrs: [NSAttributedString.Key: Any], _ sz: NSSize) {
                (s as NSString).draw(at: NSPoint(x: x, y: midY - sz.height / 2), withAttributes: attrs)
                x += sz.width
            }

            drawText(name, nameAttr, nameSize); x += gap
            if !compact { drawText(lv, lvAttr, lvSize); x += gap }   // "Lv--" hidden in compact mode

            // Fused HP unit: single rounded pill, black "HP" cap + white gauge; only inner fill is colored.
            let unit = NSRect(x: x, y: midY - unitH / 2, width: hpUnitW, height: unitH)
            let labelW = hpUnitW - gaugePartW
            let unitPath = NSBezierPath(roundedRect: unit, xRadius: 3, yRadius: 3)
            NSGraphicsContext.current?.saveGraphicsState()
            unitPath.setClip()
            black.setFill(); NSRect(x: unit.minX, y: unit.minY, width: labelW, height: unitH).fill()
            NSColor.white.setFill(); NSRect(x: unit.minX + labelW, y: unit.minY, width: gaugePartW, height: unitH).fill()
            let innerInset: CGFloat = 3
            let innerFull = gaugePartW - innerInset
            if frac > 0 {
                hpColor.setFill()
                NSRect(x: unit.minX + labelW, y: unit.minY + innerInset,
                       width: innerFull * frac, height: unitH - innerInset * 2).fill()
            }
            NSGraphicsContext.current?.restoreGraphicsState()
            black.setStroke(); unitPath.lineWidth = 1.5; unitPath.stroke()
            // divider + HP label
            black.setStroke()
            let div = NSBezierPath()
            div.move(to: NSPoint(x: unit.minX + labelW, y: unit.minY))
            div.line(to: NSPoint(x: unit.minX + labelW, y: unit.maxY))
            div.lineWidth = 1; div.stroke()
            (hpLabel as NSString).draw(
                at: NSPoint(x: unit.minX + (labelW - hpLabelSize.width) / 2, y: midY - hpLabelSize.height / 2),
                withAttributes: hpLabelAttr)
            x += hpUnitW + gap

            drawText(hpText, hpTextAttr, hpTextSize); x += flavorGap

            // Dialogue slot: fixed width, text centered, crossfade + vertical slide.
            let slotX = x
            func drawSlot(_ text: String, _ a: CGFloat, slideUp: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: slotFont, .foregroundColor: black.withAlphaComponent(max(0, min(1, a)))]
                let sz = (text as NSString).size(withAttributes: attrs)
                let cx = slotX + (slotW - sz.width) / 2   // center within reserved slot
                (text as NSString).draw(at: NSPoint(x: cx, y: midY - sz.height / 2 + slideUp), withAttributes: attrs)
            }
            if let secondary = secondary {
                drawSlot(secondary, 1 - alpha, slideUp: alpha * 4)        // outgoing rises & fades
                drawSlot(primary, alpha, slideUp: -(1 - alpha) * 4)      // incoming rises into place
            } else {
                drawSlot(primary, 1, slideUp: 0)
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    func refresh() {
        fetchUsage { [weak self] result in
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    func apply(_ result: UsageResult) {
        last = result

        // Backoff bookkeeping, then schedule the next fetch — skipped entirely
        // in mock mode so UI testing never triggers a real network call.
        if !isMocking {
            if result.rateLimited {
                backoff = backoff == 0 ? REFRESH_SECONDS : min(backoff * 2, MAX_BACKOFF)
            } else if result.error == nil {
                backoff = 0   // success clears any backoff
            }
            scheduleNext()
        }

        if result.rateLimited {
            // Show the dozing widget in ALL cases — with prior data (gray bar at last
            // HP) or without (placeholder --/100). Never fall back to plain text.
            rebuildMenu()
            sleeping = true
            lastSignature = ""
            renderNow()
            return
        }
        sleeping = false

        if result.error != nil {
            hasData = false
            setTitle(text: " C ⚠", color: .systemRed)
            rebuildMenu()
            return
        }

        lastLimits = result.limits
        updateDriver(resetCycle: false)
        rebuildMenu()
    }

    /// Point the widget at the currently selected limit (default: 5-hour session).
    func updateDriver(resetCycle: Bool) {
        let driver = lastLimits.first(where: { $0.kind == selectedKind })
            ?? lastLimits.first(where: { $0.kind == "session" })
            ?? lastLimits.max(by: { $0.percent < $1.percent })

        if let d = driver {
            driverUsed = d.percent
            driverResets = d.resetsAt
            if !hasData || resetCycle { cycleStart = Date() }
            hasData = true
            lastSignature = ""                    // force an immediate redraw
            renderNow()
        } else {
            hasData = false
            setTitle(text: " Claude —", color: .secondaryLabelColor)
        }
    }

}
