import Cocoa

enum BattleScreen {
    case root, usage, more, skins, battle

    var message: String {
        switch self {
        case .root:   return "무엇을 할까?"
        case .usage:  return "어떤 한도를 볼까?"
        case .more:   return "어떤 걸 해볼까?"
        case .skins:  return "누구로 바꿀까?"
        case .battle: return "무엇을 할까?"
        }
    }
}

/// One cell of the 2x2 menu. `enabled == false` draws it dimmed and ignores clicks.
struct BattleItem {
    let title: String
    let action: BattleAction
    var enabled = true
}

enum BattleAction {
    case openUsage, openMore, openSkins, openBattle, back
    case tackle                 // 몸통박치기 — animated entirely inside the view
    case pickLimit(String)      // limit `kind`
    case pickSkin(String)       // skin `id`
    case toggleCompact
    case checkUpdate
    case refresh
    case quit
    case none                   // reserved slot, not yet decided
}

final class BattleView: NSView {
    /// Used% of the tracked limit — the same number the menu-bar widget shows.
    /// Re-read from the delegate after a limit switch, so the sprite's HP and Lv
    /// follow the menu-bar widget.
    var usedPercent: Int
    /// The limits available on this account, in display order.
    var limits: [Limit]
    /// Which limit is tracked right now (a `kind`).
    var selectedKind: String
    /// Whether compact mode is on — flips the 좁게 보기/넓게 보기 label.
    var compactOn: Bool
    /// The chosen skin's id, and how many pets so far (gates the shiny).
    var skinID: String
    var petCount: Int

    /// Actions are performed by the app delegate; the view only draws and routes.
    var perform: (BattleAction) -> Void = { _ in }
    /// Called when Escape/back is pressed at the root — closes the panel.
    var onDismiss: () -> Void = {}

    var screen: BattleScreen = .root
    var cursor = 0

    // ── Animation
    private var animTimer: Timer?
    private var tick = 0
    /// Claude's hop. The widget's version is 1px because it lives in a 22px menu
    /// bar; here there is room for a taller, slower arc.
    private var bob: CGFloat = 0
    static let clawdHop: CGFloat = 4          // px at the top of the hop
    /// The bug drifts toward a target, then picks a new one. Interpolating toward
    /// a target (rather than jittering each frame) is what makes it read as
    /// floating instead of vibrating.
    private var bugOffset = NSPoint.zero
    private var bugTarget = NSPoint.zero
    static let bugDriftX: CGFloat = 16        // max px from center, horizontally
    static let bugDriftY: CGFloat = 13        // less vertical room: indicators

    // ── Easter egg: 무당벌레
    /// The enemy's black HP plate, recorded while drawing it (the same trick the
    /// widget's sprite hitbox uses) so mouseDown can hit-test it without
    /// recomputing the indicator layout.
    private var enemyHPRect = NSRect.zero
    /// The skin picker's top-right "뒤로가다" button, recorded while drawing so
    /// mouseDown can hit-test it (the picker has no 2x2 cell for going back).
    private var skinBackRect = NSRect.zero
    private var hpClicks = 0
    /// Purely cosmetic and deliberately not persisted: closing the panel resets
    /// the bug, so finding it again is part of the joke.
    private var ladybug = false
    var bugPalette: [Character: NSColor] { ladybug ? ladybugColors : bugColors }

    /// A transient two-line barker that takes over the dialogue slot when the egg
    /// fires, then expires back to the screen's own message. Two lines because the
    /// beat is a pause and then the reveal — one line would give it all away at once.
    private var flashLines: [String] = []
    private var flashUntil: Date?
    private var flashing: Bool {
        guard let u = flashUntil else { return false }
        return Date() < u
    }

    // ── Shiny sparkle
    /// When the entrance burst started, or nil once it has run. Set on appear and
    /// on switching *to* the shiny, so picking it in the menu replays the effect —
    /// that moment is the payoff for 50 pets and should not pass unmarked.
    private var sparkleStart: Date?
    /// The player's sprite frame, recorded while drawing so the burst can be placed
    /// over it without recomputing the battle-area layout.
    private var playerSpriteRect = NSRect.zero
    var isShiny: Bool { skin(id: skinID).isRare }

    /// The enemy bug's level and HP, rolled fresh each time a battle panel opens
    /// (a new BattleView is built per open). Purely cosmetic — unrelated to the
    /// account's real usage, which only drives the player's side.
    let enemyLevel = Int.random(in: 2...60)
    static let enemyMaxHP = 100
    private var enemyHP = Int.random(in: 20...BattleView.enemyMaxHP)
    var enemyFrac: CGFloat { CGFloat(enemyHP) / CGFloat(Self.enemyMaxHP) }

    // ── 몸통박치기 (tackle)
    /// Frame counter for the attack animation; -1 when idle. Driven by step(), so
    /// the whole sequence runs on the existing 12fps timer.
    private var attackTick = -1
    /// A tackle that cannot land (the bug is down to its last HP) plays the lunge
    /// but never flashes the bug — it just reports the miss.
    private var attackMissed = false
    /// Ticks: 0-2 lunge out and back (one tick per leg, so the swing reads fast),
    /// 3-10 the hit flash (2 blinks).
    private static let lungeEnd = 3
    private static let flashEnd = 11

    /// Claude's lunge toward the upper right, then back.
    private var attackOffset: NSPoint {
        switch attackTick {
        case 0:  return NSPoint(x: 6, y: 5)
        case 1:  return NSPoint(x: 12, y: 10)
        case 2:  return NSPoint(x: 6, y: 5)
        default: return .zero
        }
    }
    /// Retro hit flash: the bug blanks for two ticks, shows for two, twice.
    private var bugHidden: Bool {
        guard !attackMissed, attackTick >= Self.lungeEnd, attackTick < Self.flashEnd else { return false }
        return ((attackTick - Self.lungeEnd) / 2) % 2 == 0
    }
    /// The squeezed-shut face holds for the whole flash, not just the visible frames.
    private var bugHurting: Bool {
        !attackMissed && attackTick >= Self.lungeEnd && attackTick < Self.flashEnd
    }

    /// Start a tackle. Damage is random but never more than half the bug's remaining
    /// HP, so it can never be knocked out; at 1 HP nothing can land and it misses.
    func startTackle() {
        guard attackTick < 0 else { return }        // ignore re-entry mid-swing
        let maxDamage = enemyHP / 2
        attackMissed = maxDamage < 1
        attackTick = 0
        needsDisplay = true
    }

    func startSparkle() {
        guard isShiny else { return }
        sparkleStart = Date()
        needsDisplay = true
    }

    init(frame: NSRect, usedPercent: Int, limits: [Limit], selectedKind: String,
         compactOn: Bool, skinID: String, petCount: Int) {
        self.usedPercent = usedPercent
        self.limits = limits
        self.selectedKind = selectedKind
        self.compactOn = compactOn
        self.skinID = skinID
        self.petCount = petCount
        super.init(frame: frame)
        wantsLayer = true
    }

    /// This account's skin as chosen; and which skins are pickable right now.
    var skinColors: [Character: NSColor] { skin(id: skinID).battleColors }
    func isUnlocked(_ s: ClawdSkin) -> Bool { petCount >= s.unlockPets }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Start/stop the animation with the view's presence on screen, so a closed
    /// panel never keeps a timer (and a retain cycle) alive.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animTimer?.invalidate()
        animTimer = nil
        guard window != nil else { return }
        pickBugTarget()
        startSparkle()          // the shiny announces itself on entry; no-op otherwise
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    /// Aim somewhere new, but never near where we already are: a target next to
    /// the current position produces a twitch, not a drift.
    private func pickBugTarget() {
        let rx = Self.bugDriftX, ry = Self.bugDriftY
        for _ in 0..<8 {
            let p = NSPoint(x: .random(in: -rx...rx), y: .random(in: -ry...ry))
            if hypot(p.x - bugOffset.x, p.y - bugOffset.y) > rx * 0.8 { bugTarget = p; return }
        }
        bugTarget = NSPoint(x: -bugOffset.x, y: -bugOffset.y)   // fall back: swing across
    }

    private func step() {
        tick += 1

        // Tackle: advance the swing. Damage lands the moment the flash starts, so
        // the gauge drops in step with the blinking.
        var attacking = false
        if attackTick >= 0 {
            attackTick += 1
            attacking = true
            if attackTick == Self.lungeEnd {
                if attackMissed {
                    flashLines = ["클로드의 공격이", "빗나갔다!"]
                    flashUntil = Date().addingTimeInterval(LADYBUG_FLASH_HOLD)
                    attackTick = -1                  // nothing left to animate
                } else {
                    enemyHP -= Int.random(in: 1...(enemyHP / 2))
                }
            } else if attackTick >= Self.flashEnd {
                attackTick = -1                      // swing over
            }
        }

        // Claude hops in a 4px arc. A sine gives the arc; rounding keeps it on
        // the pixel grid, so the sprite never lands on a half-pixel and blurs.
        let phase = Double(tick % 24) / 24.0
        let newBob = (CGFloat(sin(phase * .pi * 2) * Double(Self.clawdHop))).rounded()

        // Bug: ease toward the target, then choose another once close enough.
        let dx = bugTarget.x - bugOffset.x, dy = bugTarget.y - bugOffset.y
        bugOffset = NSPoint(x: bugOffset.x + dx * 0.085, y: bugOffset.y + dy * 0.085)
        if abs(dx) + abs(dy) < 1.5 { pickBugTarget() }

        // The sparkle animates on its own clock, so it has to force repaints for
        // its whole run — otherwise a still frame (no bob, no drift) would freeze
        // it mid-burst. Clear it when done so we stop repainting for nothing.
        var sparkling = false
        if let s = sparkleStart {
            if Date().timeIntervalSince(s) > SPARKLE_DURATION { sparkleStart = nil }
            else { sparkling = true }
        }

        // The barker expires on a clock too, and its last frame needs one repaint
        // to clear — without this it would linger until the next bob happened to
        // trigger a redraw.
        var flashExpired = false
        if let u = flashUntil, Date() >= u { flashUntil = nil; flashExpired = true }

        // draw(_:) repaints the whole panel (the rounded background makes a
        // partial repaint fiddly), so only ask for one when something moved.
        let moved = newBob != bob || abs(dx) + abs(dy) > 0.05
        bob = newBob
        if moved || sparkling || flashExpired || attacking { needsDisplay = true }
    }

    deinit { animTimer?.invalidate() }

    override var acceptsFirstResponder: Bool { true }

    static let bigFontSize: CGFloat = 17
    static let hpLabelSize: CGFloat = 11
    static let cellH: CGFloat = 32
    let dialogH: CGFloat = cellH * 2 + 8 + 24
    let pad: CGFloat = 12
    let boxBorder: CGFloat = 4
    /// Horizontal breathing room inside each menu cell. Without it the right
    /// column's text sits flush against the container's border.
    ///
    /// These numbers are load-bearing together, alongside BATTLE_W: the longest
    /// label ("사용량 선택" / "색상 커스텀", ~90pt at 16pt) must fit in
    ///   cellWidth - (cellPadX + cursorW) - cellPadX
    /// while the longest message ("어떤 한도를 볼까?", ~136pt) still fits the
    /// left area. Both clear by only a few points — widen the cursor gap or the
    /// padding without also widening the panel and text starts clipping.
    let cellPadX: CGFloat = 12
    let cursorW: CGFloat = 18       // cursor column: ▶ plus the gap before the label
    let menuRatio: CGFloat = 0.60
    static let itemFontSize: CGFloat = 16

    /// The four cells of the current page. 사용량 is built from the account's
    /// real limits, so an account without a scoped (Fable) limit never shows one.
    var items: [BattleItem] {
        switch screen {
        case .root:
            return [
                BattleItem(title: "싸우다", action: .openBattle),
                BattleItem(title: "사용량 선택", action: .openUsage),
                BattleItem(title: "더보기", action: .openMore),
                BattleItem(title: "종료하다", action: .quit),
            ]
        case .battle:
            return [
                BattleItem(title: "몸통박치기", action: .tackle),
                BattleItem(title: "—", action: .none, enabled: false),
                BattleItem(title: "—", action: .none, enabled: false),
                BattleItem(title: "뒤로가다", action: .back),
            ]
        case .usage:
            let order = ["session", "weekly_all", "weekly_scoped"]
            let sorted = limits.sorted {
                (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9)
            }
            var out = sorted.prefix(3).map {
                BattleItem(title: shortLabel(for: $0), action: .pickLimit($0.kind))
            }
            while out.count < 3 { out.append(BattleItem(title: "—", action: .none, enabled: false)) }
            out.append(BattleItem(title: "뒤로가다", action: .back))
            return out
        case .more:
            return [
                BattleItem(title: compactOn ? "넓게 보기" : "좁게 보기", action: .toggleCompact),
                BattleItem(title: "버전 확인", action: .checkUpdate),
                BattleItem(title: "색상 커스텀", action: .openSkins),
                BattleItem(title: "뒤로가다", action: .back),
            ]
        case .skins:
            return []   // the skin picker draws its own grid, not a 2x2 menu
        }
    }

    /// The six skins, in party order.
    var skinCells: [ClawdSkin] { ALL_SKINS }

    /// The full menu labels ("세션 (5시간)") do not fit a cell, so shorten them
    /// to the period each limit covers.
    private func shortLabel(for l: Limit) -> String {
        switch l.kind {
        case "session":    return "5시간"
        case "weekly_all": return "7일"
        case "weekly_scoped":
            // The scope name is a model name from the API (e.g. "Fable").
            // Transliterate the ones we know; otherwise show what the API gave.
            let ko = ["Fable": "페이블", "Opus": "오퍼스", "Sonnet": "소네트", "Haiku": "하이쿠"]
            let n = l.scopeName ?? "7일"
            return ko[n] ?? n
        default:
            return l.kind
        }
    }

    // The player's indicator carries four rows (name / gauge / numbers / exp),
    // so it must be taller than the enemy's or the numbers collide with the gauge.
    let enemyBoxSize = NSSize(width: 195, height: 44)
    // 64 is about the floor: below ~62 the HP numbers start overlapping the exp
    // bar, since name/gauge hang from the top and numbers/exp stack from the base.
    let playerBoxSize = NSSize(width: 200, height: 64)

    override func draw(_ dirty: NSRect) {
        let r = bounds
        GB_BG.setFill()
        let outer = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        outer.fill()
        GB_INK.setStroke(); outer.lineWidth = 2; outer.stroke()

        // The skin picker takes the whole panel, like the party screen.
        if screen == .skins { drawSkinPicker(); return }

        // Battle area first, dialog box over it: that is what crops Claude's legs.
        drawBattleArea(NSRect(x: r.minX, y: r.minY + dialogH,
                              width: r.width, height: r.height - dialogH))
        drawDialogBox(dialogBox)
    }

    private func drawBattleArea(_ area: NSRect) {
        let enemyBox = NSRect(x: area.minX + 14, y: area.maxY - enemyBoxSize.height - 12,
                              width: enemyBoxSize.width, height: enemyBoxSize.height)
        let playerBox = NSRect(x: area.maxX - playerBoxSize.width - 14, y: area.minY + 6,
                               width: playerBoxSize.width, height: playerBoxSize.height)

        // Sprites are centered in whatever space the indicators leave, so changing
        // an indicator's size moves the sprite with it instead of stranding it.
        // The bug floats around that center; Claude hops in place.
        // bugBase already carries hand-placed shading (D/G/B tones), so it is
        // drawn as-is. battleShaded would re-tone the 'B' body cells by light
        // direction and fight that hand shading.
        // While a tackle lands the bug wears the squeezed-shut face and blinks out
        // entirely on alternating frames — the Gen-2 hit flash.
        let eGrid = bugHurting ? bugHurtBase : bugBase
        let eCell: CGFloat = 4.0
        let eSize = spriteSize(eGrid, cell: eCell)
        let eField = NSRect(x: enemyBox.maxX, y: playerBox.maxY,
                            width: area.maxX - enemyBox.maxX, height: area.maxY - playerBox.maxY)
        if !bugHidden {
            drawSprite(eGrid, origin: NSPoint(x: eField.midX - eSize.width / 2 - 9 + bugOffset.x,
                                              y: eField.midY - eSize.height / 2 - 10 + bugOffset.y),
                       cell: eCell, colors: bugPalette)
        }

        // The dialog box swallowing the lower body is intentional — Gen-2 back
        // sprites are cropped at the waist the same way, so do not "fix" this by
        // raising the sprite. The grid below the crop line is drawn but never seen.
        let pGrid = clawdBackGrid()
        let pCell: CGFloat = 5.8
        let pSize = spriteSize(pGrid, cell: pCell)
        let pField = NSRect(x: area.minX, y: area.minY,
                            width: playerBox.minX - area.minX, height: enemyBox.minY - area.minY)
        // attackOffset lunges Claude toward the upper right during a tackle.
        let pOrigin = NSPoint(x: pField.midX - pSize.width / 2 + attackOffset.x,
                              y: pField.midY - pSize.height / 2 - 45 + bob + attackOffset.y)
        drawSprite(pGrid, origin: pOrigin, cell: pCell, colors: skinColors)
        playerSpriteRect = NSRect(origin: pOrigin, size: pSize)

        drawIndicator(enemyBox, name: BATTLE_ENEMY_NAME, level: enemyLevel,
                      frac: enemyFrac, isPlayer: false)
        let remaining = max(0, min(100, 100 - usedPercent))
        // The ★ rides on the name so it inherits the indicator's layout. The name
        // is the shortest field there, so the extra glyph has room; see
        // docs/battle-ui.md before adding anything wider.
        drawIndicator(playerBox, name: isShiny ? "클로드\(SHINY_MARK)" : "클로드", level: usedPercent,
                      frac: CGFloat(remaining) / 100, isPlayer: true, remaining: remaining)

        // Sparkles last, so they sit over the sprite and the indicators both.
        if let s = sparkleStart, isShiny {
            let t = Date().timeIntervalSince(s) / SPARKLE_DURATION
            drawSparkles(in: playerSpriteRect, t: t, gold: SHINY_GOLD)
        }
    }

    /// Gen-2 indicator: name (larger) + level (smaller) on one baseline, a thin
    /// rectangular gauge, and a frame made of a thick vertical band plus a thin
    /// bottom rule (~5x thinner) ending in a half-arrowhead. The player's is
    /// mirrored, and carries big HP numbers plus a container-less exp bar that
    /// fills right-to-left.
    /// A GB-style half-arrowhead built from stacked pixel rows instead of a smooth
    /// triangle, so its hypotenuse steps like the reference sprite. The tip keeps a
    /// 1px stub rather than a needle point, giving the rounded-off look.
    /// `baseX` is the vertical (base) edge; the tip sits `w` away toward `tipDir`
    /// (+1 = tip to the right, -1 = tip to the left). Rows stack up from `y`.
    private func drawPixelArrow(baseX: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, tipDir: CGFloat) {
        let px: CGFloat = 1.375           // one "pixel" — matches the sprite cell feel
        let rows = max(1, Int((h / px).rounded()))
        let stub: CGFloat = px            // blunt tip: shortest row is 1px wide, not 0
        for r in 0..<rows {
            // Bottom row is full width (w); each row up loses a step, down to the stub.
            let t = CGFloat(r) / CGFloat(rows)
            let rowW = max(stub, w * (1 - t))
            let rowY = y + CGFloat(r) * px
            let rowX = tipDir > 0 ? baseX : baseX - rowW
            NSRect(x: rowX, y: rowY, width: rowW, height: px).fill()
        }
    }

    enum Corner { case bottomLeft, topRight, bottomRight }

    /// Rounds one corner of a filled shape by painting stepped pixel triangles in
    /// the background color — the same staircase look as drawPixelArrow, but
    /// subtractive. `x,y` is the corner origin; `size` is the band thickness so the
    /// notch scales with it. Must run inside the same non-antialiased context, and
    /// the current fill color is overwritten (caller re-sets ink if needed).
    private func drawCornerNotch(x: CGFloat, y: CGFloat, size: CGFloat, corner: Corner) {
        let px: CGFloat = 1.375
        let steps = max(1, Int((size * 0.5 / px).rounded()))   // notch ~half the thickness
        GB_BG.setFill()
        for s in 0..<steps {
            let cut = CGFloat(steps - s) * px      // widest cut at the very corner
            let off = CGFloat(s) * px
            switch corner {
            case .bottomLeft:
                NSRect(x: x, y: y + off, width: cut, height: px).fill()
            case .topRight:
                NSRect(x: x + size - cut, y: y - off - px, width: cut, height: px).fill()
            case .bottomRight:
                NSRect(x: x + size - cut, y: y + off, width: cut, height: px).fill()
            }
        }
    }

    /// 계단식으로 안쪽 코너를 채운다(둥근 안쪽 모서리). x,y는 코너 기준점,
    /// 좌측 위에서 우측 아래로 내려오는 계단을 GB_INK로 그린다.
    private func drawCornerFill(x: CGFloat, y: CGFloat, size: CGFloat) {
        let px: CGFloat = 1.375
        let steps = max(1, Int((size * 0.5 / px).rounded()))
        GB_INK.setFill()
        for s in 0..<steps {
            let w = CGFloat(steps - s) * px       // 위로 갈수록 넓게
            let rowY = y + CGFloat(s) * px         // 코너에서 아래로 쌓기
            NSRect(x: x, y: rowY, width: w, height: px).fill()
        }
    }


    private func drawIndicator(_ box: NSRect, name: String, level: Int, frac: CGFloat,
                               isPlayer: Bool, remaining: Int = 0) {
        let title = NSMutableAttributedString(string: name,
            attributes: [.font: pixelFont(18), .foregroundColor: GB_INK])
        title.append(NSAttributedString(string: ":L\(level)",
            attributes: [.font: pixelFont(14), .foregroundColor: GB_INK]))
        let ts = title.size()

        let bandW: CGFloat = 9.5
        let lineH: CGFloat = 2       // bottom rule; integer so both indicators' rules
                                     // land on the same pixel weight (no subpixel drift)
        let arrowW: CGFloat = 13.75  // 1.25× the old 11
        let arrowH: CGFloat = 8
        let lineY = box.minY
        // Player-only: a black connector strip where the right vertical band meets
        // the HP bar (top) and the exp/arrow line (bottom). Each strip is this wide
        // and overlays the bar, so both gauges lose this much of their full width.
        let junctionW: CGFloat = 5

        let unitH: CGFloat = 12
        let unitY = box.maxY - ts.height - unitH - 2
        let labelW: CGFloat = 28
        let unit = isPlayer
            ? NSRect(x: box.minX + 8, y: unitY, width: box.width - 8 - bandW + 1, height: unitH)
            : NSRect(x: box.minX + bandW - 1, y: unitY, width: box.width - bandW - 3, height: unitH)

        // The name starts where the gauge starts — i.e. just past the black
        // "HP:" cap, above the boundary between the cap and the bar. labelW is
        // the cap's width, so unit.minX + labelW is the gauge's left edge.
        let gaugeStartX = unit.minX + labelW
        title.draw(at: NSPoint(x: gaugeStartX, y: box.maxY - ts.height))

        // The enemy's plate is the easter egg's hit target; remember where it
        // landed so mouseDown does not have to redo this layout.
        if !isPlayer { enemyHPRect = unit }

        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        GB_INK.setFill(); unit.fill()
        // The enemy's track stops short, leaving the thick black cap on its right.
        // The player's right margin is junctionW: the unit is black full-height, so
        // that margin reads as the top connector strip, and the gauge stops before it.
        let trackR: CGFloat = isPlayer ? junctionW : 8   // enemy cap doubled (was 4)
        // The track background is GB_BG, not white, so the empty part of the gauge
        // and the padding above/below it read as "no track" — the colored gauge
        // just floats on the panel. It flushes to the unit's TOP so no black rule
        // shows above; a thin black rule remains below. The colored gauge inside is
        // 0.75× the old height (9→6.75) and centered in the track.
        let trackX = unit.minX + labelW
        let trackW = unit.width - labelW - trackR
        let track = NSRect(x: trackX, y: unit.minY + 1.5,
                           width: trackW, height: unitH - 1.5)   // top flush, ~1.5 below
        GB_BG.setFill(); track.fill()
        if frac > 0 {
            let gaugeH: CGFloat = (unitH - 3) * 0.75 * 0.75   // thinned once more (0.75×)
            gaugeColor(frac).setFill()
            NSRect(x: track.minX, y: track.minY + (track.height - gaugeH) / 2,
                   width: track.width * frac, height: gaugeH).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        let hpAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(Self.hpLabelSize),
                                                     .foregroundColor: GB_YELLOW]
        let hpLabel = "HP:" as NSString
        let hs = hpLabel.size(withAttributes: hpAttr)
        hpLabel.draw(at: NSPoint(x: unit.minX + 5, y: unit.minY + (unitH - hs.height) / 2),
                     withAttributes: hpAttr)

        if isPlayer {
            let numAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(20), .foregroundColor: GB_INK]
            let num = "\(remaining)/ 100" as NSString
            let ns = num.size(withAttributes: numAttr)
            num.draw(at: NSPoint(x: box.maxX - bandW - 6 - ns.width, y: unit.minY - ns.height - 1),
                     withAttributes: numAttr)
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        GB_INK.setFill()
        if isPlayer {
            let pBandX = box.maxX - bandW
            NSRect(x: pBandX, y: lineY, width: bandW, height: unit.maxY - lineY).fill()
            let tipX = box.minX - 6
            NSRect(x: tipX + arrowW, y: lineY, width: box.maxX - (tipX + arrowW), height: lineH).fill()
            // Tip points left; base edge sits at tipX + arrowW.
            drawPixelArrow(baseX: tipX + arrowW, y: lineY, w: arrowW, h: arrowH, tipDir: -1)
            // Round the band's outer (right) corners, top and bottom.
            drawCornerNotch(x: pBandX, y: unit.maxY, size: bandW, corner: .topRight)
            drawCornerNotch(x: pBandX, y: lineY, size: bandW, corner: .bottomRight)
            GB_INK.setFill()   // notch left GB_BG selected; restore for the exp bar path below
            // Bottom connector strip: black, junctionW wide, arrowhead-tall, flush to
            // the band's left edge. Overlays the line/exp area at the junction.
            NSRect(x: pBandX - junctionW, y: lineY, width: junctionW, height: arrowH).fill()
            let expX = tipX + arrowW + 2
            // Exp bar total width loses junctionW so its right edge sits flush
            // against the strip's left edge (pBandX - junctionW).
            let exp = NSRect(x: expX, y: lineY + lineH + 2,
                             width: (box.maxX - bandW) - expX - junctionW, height: 4)
            GB_EXP.setFill()
            NSRect(x: exp.maxX - exp.width * 0.55, y: exp.minY,
                   width: exp.width * 0.55, height: exp.height).fill()
        } else {
            // Enemy bracket: a vertical band on the LEFT (outside the HP bar so it
            // never covers the "HP:" cap), a bottom rule, and an arrowhead on the
            // right — joined as one right-angled ⌐ shape.
            let bandGap: CGFloat = 4
            let eBandW = bandW * 0.75           // thinner band (0.75×)
            let eBandH = (unit.maxY - lineY) * 1.25   // taller band (1.25×)
            let bandX = box.minX - bandGap      // original left position (clears "HP:")
            let eBandBottom = (unit.maxY - eBandH).rounded()   // pixel-align the rule
            // Arrowhead base aligns with the HP bar's right edge (unit.maxX): the
            // triangle sits directly under the gauge's end, not past the box.
            let endX = unit.maxX + arrowW
            // Bottom rule spans from ruleX to the arrowhead's base. ruleX is the
            // horizontal start of the rule ONLY — decoupled from bandX so the rule
            // can slide right to meet the band's right edge without dragging the
            // vertical band with it. Draw the rule FIRST at eBandBottom with pure
            // lineH, then the band stops just above it (its bottom == rule's top) so
            // the band never stacks onto the rule and thickens it.
            // Rule and band share bandX, so the band, rule, and stepped notch all
            // align on the same left edge — no overhang. ruleX stays separate only
            // so the rule's start can be nudged later without moving the band.
            let ruleX = bandX + 6.5
            NSRect(x: ruleX, y: eBandBottom + 1, width: (endX - arrowW) - ruleX, height: lineH).fill()
            NSRect(x: bandX, y: eBandBottom + lineH,
                   width: eBandW, height: eBandH - lineH).fill()
            // Tip points right; base edge sits at endX - arrowW, on the same rule.
            drawPixelArrow(baseX: endX - arrowW, y: eBandBottom + 1, w: arrowW, h: arrowH, tipDir: 1)
            // Restore the stepped, rounded bottom-left corner of the band.
            drawCornerNotch(x: bandX, y: eBandBottom + lineH, size: eBandW, corner: .bottomLeft)
            drawCornerFill(x: bandX + eBandW, y: eBandBottom + lineH, size: eBandW + 3)
            GB_INK.setFill()
        }
        // Restore, or the dialog box's curves drawn next come out jagged too.
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    var dialogBox: NSRect {
        NSRect(x: bounds.minX + pad, y: bounds.minY + pad,
               width: bounds.width - pad * 2, height: dialogH - pad * 2)
    }
    var menuBox: NSRect {
        let w = dialogBox.width * menuRatio
        return NSRect(x: dialogBox.maxX - w, y: dialogBox.minY, width: w, height: dialogBox.height)
    }
    var menuInner: NSRect { menuBox.insetBy(dx: boxBorder, dy: boxBorder) }

    /// The four cells divide menuInner exactly, with no gaps between them.
    /// (Text is inset within each cell; see cellPadX.)
    func itemRect(_ i: Int) -> NSRect {
        let col = CGFloat(i % 2), row = CGFloat(i / 2)
        let w = menuInner.width / 2, h = menuInner.height / 2
        return NSRect(x: menuInner.minX + col * w, y: menuInner.maxY - (row + 1) * h,
                      width: w, height: h)
    }

    // ── Skin picker (party-style screen)

    /// A locked skin shows as a flat gray silhouette so its color stays a surprise.
    private var lockedColors: [Character: NSColor] {
        ["K": GB_INK, "B": rgb(0x6A, 0x66, 0x72), "D": rgb(0x6A, 0x66, 0x72), "L": rgb(0x6A, 0x66, 0x72)]
    }

    /// Area the 3x2 skin grid fills, below the title row.
    private var skinGrid: NSRect {
        let m: CGFloat = 12, titleH: CGFloat = 30
        return NSRect(x: bounds.minX + m, y: bounds.minY + m,
                      width: bounds.width - m * 2, height: bounds.height - m * 2 - titleH)
    }
    func skinRect(_ i: Int) -> NSRect {
        let colsN = 3, rowsN = 2, gap: CGFloat = 8
        let cw = (skinGrid.width - gap * CGFloat(colsN - 1)) / CGFloat(colsN)
        let ch = (skinGrid.height - gap * CGFloat(rowsN - 1)) / CGFloat(rowsN)
        let col = i % colsN, row = i / colsN
        return NSRect(x: skinGrid.minX + CGFloat(col) * (cw + gap),
                      y: skinGrid.maxY - CGFloat(row + 1) * ch - CGFloat(row) * gap,
                      width: cw, height: ch)
    }

    private func drawSkinPicker() {
        let titleAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(Self.itemFontSize),
                                                        .foregroundColor: GB_INK]
        let title = screen.message as NSString
        let th = title.size(withAttributes: titleAttr).height
        title.draw(at: NSPoint(x: bounds.minX + 18, y: bounds.maxY - 12 - th), withAttributes: titleAttr)

        // Top-right back button — clickable (and still Esc-able). The picker has
        // no 2x2 grid, so this is the in-UI way out.
        let back = "◀ 뒤로가다" as NSString
        let backAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(13), .foregroundColor: GB_INK]
        let bs = back.size(withAttributes: backAttr)
        let backOrigin = NSPoint(x: bounds.maxX - 18 - bs.width, y: bounds.maxY - 12 - bs.height)
        back.draw(at: backOrigin, withAttributes: backAttr)
        // Pad the hit area so the whole word is comfortably clickable.
        skinBackRect = NSRect(x: backOrigin.x - 6, y: backOrigin.y - 4,
                              width: bs.width + 12, height: bs.height + 8)

        let miniGrid = spriteGrids[.healthy]![0]
        let miniCell: CGFloat = 2.6
        let miniSize = spriteSize(miniGrid, cell: miniCell)

        for (i, s) in skinCells.enumerated() {
            let cell = skinRect(i)
            let selected = (s.id == skinID)
            let focused = (i == cursor)
            let unlocked = isUnlocked(s)

            let boxPath = NSBezierPath(roundedRect: cell, xRadius: 6, yRadius: 6)
            (selected ? NSColor.white : GB_BG).setFill(); boxPath.fill()
            GB_INK.setStroke(); boxPath.lineWidth = focused ? 3 : 1.5; boxPath.stroke()

            drawSprite(miniGrid,
                       origin: NSPoint(x: cell.midX - miniSize.width / 2, y: cell.maxY - miniSize.height - 12),
                       cell: miniCell, colors: unlocked ? s.battleColors : lockedColors)

            let name = (unlocked ? s.name : "？？？") as NSString
            let nameAttr: [NSAttributedString.Key: Any] = [
                .font: pixelFont(14),
                .foregroundColor: unlocked ? GB_INK : GB_INK.withAlphaComponent(0.4)]
            let ns = name.size(withAttributes: nameAttr)
            name.draw(at: NSPoint(x: cell.midX - ns.width / 2, y: cell.minY + 9), withAttributes: nameAttr)

            if selected {
                ("✓" as NSString).draw(at: NSPoint(x: cell.minX + 8, y: cell.maxY - 22),
                                       withAttributes: [.font: pixelFont(15), .foregroundColor: GB_INK])
            }
            // A rare skin keeps a gold ★ in its cell once earned — opposite corner
            // from the ✓, so a selected shiny shows both without them colliding.
            if s.isRare && unlocked {
                (SHINY_MARK as NSString).draw(at: NSPoint(x: cell.maxX - 22, y: cell.maxY - 22),
                                              withAttributes: [.font: pixelFont(15),
                                                               .foregroundColor: SHINY_GOLD])
            }
        }
    }

    private func drawDialogBox(_ box: NSRect) {
        GB_BG.setFill()
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        path.fill()
        GB_INK.setStroke(); path.lineWidth = 3; path.stroke()
        let inner = NSBezierPath(roundedRect: box.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4)
        GB_INK.setStroke(); inner.lineWidth = 1; inner.stroke()

        GB_BG.setFill()
        let mPath = NSBezierPath(roundedRect: menuBox, xRadius: 6, yRadius: 6)
        mPath.fill()
        GB_INK.setStroke(); mPath.lineWidth = 3; mPath.stroke()
        let mInner = NSBezierPath(roundedRect: menuBox.insetBy(dx: 4, dy: 4), xRadius: 4, yRadius: 4)
        GB_INK.setStroke(); mInner.lineWidth = 1; mInner.stroke()

        let font = pixelFont(Self.itemFontSize)
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: GB_INK]

        if flashing {
            // The barker uses both menu rows' worth of height, so it is centered on
            // the pair of baselines rather than on the top row alone.
            let lineH = ("가" as NSString).size(withAttributes: attr).height
            let gap: CGFloat = 4
            let block = lineH * CGFloat(flashLines.count) + gap * CGFloat(flashLines.count - 1)
            let midY = (itemRect(0).midY + itemRect(2).midY) / 2
            var y = midY + block / 2 - lineH
            for line in flashLines {
                (line as NSString).draw(at: NSPoint(x: box.minX + 16, y: y), withAttributes: attr)
                y -= lineH + gap
            }
        } else {
            // The message sits on the same baseline as the menu's top row, not the
            // box's vertical center, so the two columns read as one line of text.
            let msg = screen.message as NSString
            let mh = msg.size(withAttributes: attr).height
            msg.draw(at: NSPoint(x: box.minX + 16, y: itemRect(0).midY - mh / 2), withAttributes: attr)
        }

        let dim: [NSAttributedString.Key: Any] = [.font: font,
                                                  .foregroundColor: GB_INK.withAlphaComponent(0.30)]
        for (i, item) in items.enumerated() {
            let cell = itemRect(i)
            let a = item.enabled ? attr : dim
            let title = item.title as NSString
            let ih = title.size(withAttributes: a).height
            let ty = cell.midY - ih / 2
            // The cursor lives in the left padding, so the text always starts at
            // the same x whether or not this cell is selected.
            title.draw(at: NSPoint(x: cell.minX + cellPadX + cursorW, y: ty), withAttributes: a)
            if i == cursor && item.enabled {
                ("▶" as NSString).draw(at: NSPoint(x: cell.minX + cellPadX - 2, y: ty),
                                       withAttributes: attr)
            }
        }
    }

    // MARK: - Interaction

    /// Move the cursor onto the first selectable cell at or after `from`.
    private func firstEnabled(from: Int) -> Int {
        let all = items
        if all.indices.contains(from), all[from].enabled { return from }
        return all.firstIndex(where: { $0.enabled }) ?? 0
    }

    /// Columns in the current screen's grid: the skin picker is 3-wide, the menus 2.
    private var cols: Int { screen == .skins ? 3 : 2 }
    private var cellCount: Int { screen == .skins ? skinCells.count : items.count }

    func go(to screen: BattleScreen) {
        self.screen = screen
        switch screen {
        case .usage:
            // Start the cursor on the limit already being tracked.
            cursor = items.firstIndex {
                if case .pickLimit(let k) = $0.action { return k == selectedKind }
                return false
            } ?? firstEnabled(from: 0)
        case .skins:
            // Start on the skin already worn.
            cursor = skinCells.firstIndex { $0.id == skinID } ?? 0
        default:
            cursor = firstEnabled(from: 0)
        }
        needsDisplay = true
    }

    override func keyDown(with e: NSEvent) {
        var next = cursor
        let c = cols
        switch e.keyCode {
        case 126: if cursor - c >= 0 { next = cursor - c }                  // ↑
        case 125: if cursor + c < cellCount { next = cursor + c }           // ↓
        case 123: if cursor % c != 0 { next = cursor - 1 }                  // ←
        case 124: if cursor % c != c - 1 && cursor + 1 < cellCount { next = cursor + 1 }  // →
        case 36, 76: activate(); return                                     // Enter
        case 53:                                                            // Esc
            if screen == .root { onDismiss() } else { go(to: .root) }
            return
        default: super.keyDown(with: e); return
        }
        // In the menus, skip disabled cells; in the picker every cell is landable.
        if screen == .skins || (items.indices.contains(next) && items[next].enabled) {
            cursor = next
        }
        needsDisplay = true
    }

    override func mouseMoved(with e: NSEvent) { hover(e) }

    override func mouseDown(with e: NSEvent) {
        if tapEnemyHP(e) { return }
        let p = convert(e.locationInWindow, from: nil)
        // The skin picker's back button leaves the picker — same as Esc.
        if screen == .skins && skinBackRect.contains(p) { go(to: .root); return }
        hover(e)
        // A click only fires the cell it actually landed in. activate() runs off
        // the cursor, which suits the keyboard (arrows move it, Enter fires it) —
        // but for the mouse the cursor may be parked on a cell far from the click,
        // so clicking the message area or empty space would otherwise trigger it.
        let onCell = (screen == .skins)
            ? skinCells.indices.contains { skinRect($0).contains(p) }
            : items.indices.contains { itemRect($0).contains(p) && items[$0].enabled }
        if onCell { activate() }
    }

    /// Easter egg. The enemy's HP plate sits in the battle area, where no menu
    /// cell can claim the click, so counting taps here steals nothing.
    /// The skin picker replaces the whole panel, so the plate is not on screen
    /// then and the stale rect must not be hit-tested.
    private func tapEnemyHP(_ e: NSEvent) -> Bool {
        guard screen != .skins else { return false }
        let p = convert(e.locationInWindow, from: nil)
        guard enemyHPRect.contains(p) else { return false }

        hpClicks += 1
        if hpClicks >= LADYBUG_CLICKS {
            hpClicks = 0
            ladybug.toggle()
            flashLines = ladybug
                ? ["..... 오잉?!", "버그의 상태가.....!"]
                : ["..... 어라?", "원래대로 돌아왔다!"]
            flashUntil = Date().addingTimeInterval(LADYBUG_FLASH_HOLD)
            needsDisplay = true
        }
        return true
    }

    private func hover(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if screen == .skins {
            for i in skinCells.indices where skinRect(i).contains(p) {
                if cursor != i { cursor = i; needsDisplay = true }
            }
            return
        }
        let all = items
        for i in all.indices where itemRect(i).contains(p) && all[i].enabled {
            if cursor != i { cursor = i; needsDisplay = true }
        }
    }

    private func activate() {
        if screen == .skins {
            guard skinCells.indices.contains(cursor) else { return }
            let s = skinCells[cursor]
            if isUnlocked(s) { perform(.pickSkin(s.id)) }   // locked ⇒ no-op
            return
        }
        let all = items
        guard all.indices.contains(cursor), all[cursor].enabled else { return }
        switch all[cursor].action {
        case .openUsage:  go(to: .usage)
        case .openMore:   go(to: .more)
        case .openSkins:  go(to: .skins)
        case .openBattle: go(to: .battle)
        case .tackle:     startTackle()
        case .back:       go(to: .root)
        case .none:      break
        default:         perform(all[cursor].action)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
}

/// Borderless panels do not become key by default, which would leave the panel
/// unable to take the Escape key.
final class BattlePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

