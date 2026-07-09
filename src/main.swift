import Cocoa
import CoreText

// ── Claude Battery ─────────────────────────────────────────────────────────
// Personal macOS menu-bar app showing your real Claude usage limits, using the
// same source the IDE extension does: GET /api/oauth/usage with the OAuth token
// Claude Code already stored in the macOS Keychain. No external deps.

// MARK: - Config

let API_URL = "https://api.anthropic.com/api/oauth/usage"
let OAUTH_BETA = "oauth-2025-04-20"
let KEYCHAIN_SERVICE = "Claude Code-credentials"
let REFRESH_SECONDS: TimeInterval = 240      // 4 min — gentle on the usage endpoint
let MAX_BACKOFF: TimeInterval = 1800         // cap backoff at 30 min
let PIXEL_FONT_NAME = "NeoDunggeunmo"

// MARK: - Pixel font

/// Register the bundled NeoDunggeunmo pixel font so we can use it by name.
func registerPixelFont() {
    guard let url = Bundle.main.url(forResource: "neodgm", withExtension: "ttf") else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

/// Pixel font at a given size, falling back to a monospaced system font.
func pixelFont(_ size: CGFloat) -> NSFont {
    NSFont(name: PIXEL_FONT_NAME, size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
}

// MARK: - Pokémon-style flavor lines (by remaining HP %)
// Tone grounded in Pokémon-Amie/포켓파를레 emotional status messages
// (e.g. "울상을 짓고", "울어버린 것 같다").

func flavorLine(remaining: Int) -> String {
    switch remaining {
    case 90...100: return "클로드가 기운차게 뛰어다닌다!"
    case 70...89:  return "클로드가 콧노래를 부른다."
    case 45...69:  return "클로드가 조금 지친 기색이다."
    case 25...44:  return "클로드가 헥헥거리기 시작했다."
    case 10...24:  return "클로드가 울상을 짓고 있다."
    case 1...9:    return "클로드가 곧 쓰러질 것 같다!"
    default:       return "클로드가 쓰러졌다!"
    }
}

/// Shown in the dialogue slot while rate-limited (429): the app is dozing.
let SLEEP_MESSAGE = "클로드가 졸고 있다. 깨우지 말자.."

/// Korean "time until the Pokémon Center" (i.e. until the limit resets).
func resetKorean(_ date: Date?) -> String {
    guard let date = date else { return "알 수 없음" }
    let secs = Int(date.timeIntervalSinceNow)
    if secs <= 0 { return "곧 도착!" }
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    if d > 0 { return "\(d)일 \(h)시간" }
    if h > 0 { return "\(h)시간 \(m)분" }
    return "\(m)분"
}

/// Every string the dialogue slot might ever display — used to reserve a fixed
/// slot width so the widget never reflows when the text swaps or the clock ticks.
func allSlotStrings() -> [String] {
    var s = [90, 70, 45, 25, 10, 5, 0].map { flavorLine(remaining: $0) }
    // Longest plausible countdown renderings.
    s += ["포켓몬센터까지 23시간 59분", "포켓몬센터까지 6일 23시간"]
    return s
}

// MARK: - Claude pixel sprite

enum Mood { case healthy, tired, hurt, fainted }

func mood(remaining: Int) -> Mood {
    if remaining >= 50 { return .healthy }   // green
    if remaining >= 20 { return .tired }     // orange
    if remaining >= 1  { return .hurt }      // red
    return .fainted                          // 0
}

let spriteColors: [Character: NSColor] = [
    "B": NSColor(srgbRed: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1),  // Claude orange
    "D": NSColor(srgbRed: 0xA6/255, green: 0x47/255, blue: 0x2E/255, alpha: 1),  // dark outline
    "K": NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),              // near-black
    "W": NSColor.white,
    "T": NSColor(srgbRed: 0x4F/255, green: 0xA3/255, blue: 0xE3/255, alpha: 1),  // tear/sweat
    "M": NSColor(srgbRed: 0x5A/255, green: 0x22/255, blue: 0x22/255, alpha: 1),  // mouth
]

let spriteColorsFainted: [Character: NSColor] = [
    "B": NSColor(calibratedWhite: 0.72, alpha: 1),
    "D": NSColor(calibratedWhite: 0.45, alpha: 1),
    "K": NSColor(calibratedWhite: 0.15, alpha: 1),
    "W": NSColor.white,
    "T": NSColor(calibratedWhite: 0.70, alpha: 1),
    "M": NSColor(calibratedWhite: 0.30, alpha: 1),
]

// Official-style Clawd: 15 cols x 14 rows. The body/ears/arms/legs are constant;
// only the two eye rows (index 5,6) change per mood. Row 0 = top.
let clawdBase: [String] = [
    ".....DBBBBBBBD.....",
    "....DBDBBBBBDBD....",
    "..DBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBD..",   // eyes row (5) — replaced per mood
    "..DBBBBBBBBBBBBBD..",   // eyes row (6) — replaced per mood
    "DDBBBBBBBBBBBBBBBDD",   // arms
    "DDBBBBBBBBBBBBBBBDD",   // arms
    "..DBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBD..",
    "....DBD....DBD....",
    "....DBD....DBD....",
]

func makeFace(_ eyeRow5: String, _ eyeRow6: String) -> [String] {
    var g = clawdBase
    g[5] = eyeRow5
    g[6] = eyeRow6
    return g
}

// Row 0 = top. Frames per mood; index 1 (if present) is a brief blink.
let spriteGrids: [Mood: [[String]]] = [
    // content: open eyes; blink: eyes closed
    .healthy: [
        makeFace("..DBBKKBBBBBKKBBD..", "..DBBKKBBBBBKKBBD.."),
        makeFace("..DBBBBBBBBBBBBBD..", "..DBBKKBBBBBKKBBD.."),
    ],
    // tired: half-lidded (single row) + sweat drop at top-right
    .tired: [
        makeFace("..DBKKKBBBBBKKKBD..", "..DBBKKBBBBBKKBBD.."),
        makeFace("..DBBBBBBBBBBBBBD..", "..DBKKKBBBBBKKKBD.."),
    ],
    // hurt: wide worried eyes + teardrop
    .hurt: [
        makeFace("..DBBKKBBBBBKKBBD..", "..DTTKKBBBBBKKTTD.."),
        makeFace("..DBBBBBBBBBBBBBD..", "..DTTKKBBBBBKKTTD.."),
    ],
    // fainted: X-shaped eyes
    .fainted: [
        makeFace("..DBBBBBBBBBBBBBD..", "..DBKKKBBBBBKKKBD.."),
    ],
]

/// Draw a pixel grid with crisp (non-antialiased) cells; row 0 is the top.
func drawSprite(_ grid: [String], origin: NSPoint, cell: CGFloat, colors: [Character: NSColor] = spriteColors) {
    guard let ctx = NSGraphicsContext.current else { return }
    ctx.saveGraphicsState()
    ctx.shouldAntialias = false
    let rows = grid.count
    for (r, line) in grid.enumerated() {
        for (c, ch) in line.enumerated() {
            guard let color = colors[ch] else { continue }
            color.setFill()
            let x = origin.x + CGFloat(c) * cell
            let y = origin.y + CGFloat(rows - 1 - r) * cell   // flip vertically
            NSRect(x: x, y: y, width: cell, height: cell).fill()
        }
    }
    ctx.restoreGraphicsState()
}

// MARK: - Model

struct Limit {
    let kind: String        // "session", "weekly_all", "weekly_scoped"
    let percent: Int        // 0..100 used
    let resetsAt: Date?
    let scopeName: String?  // e.g. "Fable"
    let isActive: Bool
}

struct UsageResult {
    var limits: [Limit] = []
    var error: String? = nil
    var rateLimited: Bool = false   // HTTP 429 from the usage endpoint
}

// MARK: - Token

/// Read the OAuth access token from the macOS Keychain (falls back to the
/// credentials file), mirroring how Claude Code stores it.
func readAccessToken() -> String? {
    // 1) Keychain
    let task = Process()
    task.launchPath = "/usr/bin/security"
    task.arguments = ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let raw = String(data: data, encoding: .utf8),
       let token = tokenFromCredentialsJSON(raw) {
        return token
    }
    // 2) File fallback
    let home = FileManager.default.homeDirectoryForCurrentUser
    let credURL = home.appendingPathComponent(".claude/.credentials.json")
    if let raw = try? String(contentsOf: credURL, encoding: .utf8),
       let token = tokenFromCredentialsJSON(raw) {
        return token
    }
    return nil
}

func tokenFromCredentialsJSON(_ raw: String) -> String? {
    guard let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = obj["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String,
          !token.isEmpty else { return nil }
    return token
}

// MARK: - Fetch

func fetchUsage(completion: @escaping (UsageResult) -> Void) {
    guard let token = readAccessToken() else {
        completion(UsageResult(error: "로그인 토큰 없음"))
        return
    }
    guard let url = URL(string: API_URL) else {
        completion(UsageResult(error: "URL 오류")); return
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue(OAUTH_BETA, forHTTPHeaderField: "anthropic-beta")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 10

    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { completion(UsageResult(error: err.localizedDescription)); return }
        guard let http = resp as? HTTPURLResponse else {
            completion(UsageResult(error: "응답 없음")); return
        }
        if http.statusCode == 429 {
            completion(UsageResult(error: "요청이 많아 잠시 대기 중", rateLimited: true)); return
        }
        guard http.statusCode == 200, let data = data else {
            completion(UsageResult(error: "HTTP \(http.statusCode)")); return
        }
        completion(parseUsage(data))
    }.resume()
}

func parseUsage(_ data: Data) -> UsageResult {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rawLimits = obj["limits"] as? [[String: Any]] else {
        return UsageResult(error: "파싱 실패")
    }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]

    var result = UsageResult()
    for l in rawLimits {
        let kind = l["kind"] as? String ?? "?"
        let percent = (l["percent"] as? NSNumber)?.intValue ?? 0
        let isActive = l["is_active"] as? Bool ?? false
        var resetsAt: Date? = nil
        if let s = l["resets_at"] as? String {
            resetsAt = iso.date(from: s) ?? isoNoFrac.date(from: s)
        }
        var scopeName: String? = nil
        if let scope = l["scope"] as? [String: Any],
           let model = scope["model"] as? [String: Any],
           let name = model["display_name"] as? String {
            scopeName = name
        }
        result.limits.append(Limit(kind: kind, percent: percent,
                                    resetsAt: resetsAt, scopeName: scopeName,
                                    isActive: isActive))
    }
    return result
}

// MARK: - Presentation helpers

func label(for l: Limit) -> String {
    switch l.kind {
    case "session":       return "세션 (5시간)"
    case "weekly_all":    return "주간 (7일)"
    case "weekly_scoped": return "주간 \(l.scopeName ?? "")".trimmingCharacters(in: .whitespaces)
    default:              return l.kind
    }
}

/// Color by remaining headroom (traffic light).
func color(remaining frac: Double) -> NSColor {
    if frac >= 0.5 { return NSColor.systemGreen }
    if frac >= 0.2 { return NSColor.systemOrange }
    return NSColor.systemRed
}

/// Compact "resets in" string, e.g. "1h 47m", "3d 4h".
func resetIn(_ date: Date?) -> String {
    guard let date = date else { return "—" }
    let secs = Int(date.timeIntervalSinceNow)
    if secs <= 0 { return "곧" }
    let d = secs / 86400
    let h = (secs % 86400) / 3600
    let m = (secs % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

/// 10-segment battery bar filled by remaining fraction (used in the menu).
func batteryBar(remaining frac: Double) -> String {
    let n = max(0, min(10, Int(round(frac * 10))))
    return String(repeating: "█", count: n) + String(repeating: "▁", count: 10 - n)
}

/// Pokémon-style HP bar enclosed in end caps, e.g. "▕████▁▁▁▁▁▏".
func pokemonHPBar(remaining frac: Double) -> String {
    let segments = 9
    let n = max(0, min(segments, Int(round(frac * Double(segments)))))
    let fill = String(repeating: "█", count: n)
    let empty = String(repeating: "▁", count: segments - n)
    return "▕\(fill)\(empty)▏"
}

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
    var hasData = false
    var lastSignature = ""

    // Text-slot timing (seconds)
    let TIME_HOLD = 5.0             // how long the reset-countdown shows
    let FLAVOR_HOLD = 5.0            // how long the flavor line shows
    let CROSSFADE = 0.45            // swap transition duration

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerPixelFont()

        // Debug: CLAUDEBATTERY_DUMP=<path> renders sample frames and exits.
        if let dump = ProcessInfo.processInfo.environment["CLAUDEBATTERY_DUMP"] {
            dumpSamples(to: dump); exit(0)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setTitle(text: " 클로드 …", color: .secondaryLabelColor)
        // ~12fps animation loop; renderNow() is a no-op cheap-skip when nothing changed.
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.animTick += 1
            self?.renderNow()
        }

        // UI testing without hitting the network at all: CLAUDEBATTERY_MOCK=1
        // feeds fake usage data straight in and never calls fetchUsage/refresh.
        // Optional CLAUDEBATTERY_MOCK_PERCENT=NN overrides the session used%.
        if ProcessInfo.processInfo.environment["CLAUDEBATTERY_MOCK"] != nil {
            isMocking = true
            applyMock()
            return
        }
        refresh()
    }

    /// Feeds fixture data through the exact same `apply()` path real data uses,
    /// so the live menu-bar widget, animations, and click-to-switch menu all
    /// work normally — with zero network calls (apply() skips scheduleNext()
    /// while isMocking, so no timer ever fires a real fetchUsage()).
    func applyMock() {
        let env = ProcessInfo.processInfo.environment
        let sessionPct = Int(env["CLAUDEBATTERY_MOCK_PERCENT"] ?? "") ?? 41
        let now = Date()
        var mock = UsageResult()
        mock.limits = [
            Limit(kind: "session", percent: sessionPct,
                  resetsAt: now.addingTimeInterval(3600 * 2 + 60 * 13), scopeName: nil, isActive: false),
            Limit(kind: "weekly_all", percent: 55,
                  resetsAt: now.addingTimeInterval(3600 * 24 * 3), scopeName: nil, isActive: true),
            Limit(kind: "weekly_scoped", percent: 10,
                  resetsAt: now.addingTimeInterval(3600 * 24 * 3), scopeName: "Fable", isActive: false),
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
        let timeText = "포켓몬센터까지 " + resetKorean(driverResets)
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

        let bob = isFainted ? 0 : (animTick / 6) % 2
        let phase = animTick % 24
        var blink = isFainted ? false : (phase == 0 || phase == 1)

        let primary: String, secondary: String?, alpha: CGFloat
        if sleeping {
            // Dozing: closed eyes, no swap — just the sleep line.
            blink = true
            primary = SLEEP_MESSAGE; secondary = nil; alpha = 1
        } else {
            let elapsed = Date().timeIntervalSince(cycleStart)
            (primary, secondary, alpha) = slotTexts(elapsed: elapsed, remaining: remaining)
        }

        let sig = "\(used)|\(hpUnknown)|\(bob)|\(blink)|sleep=\(sleeping)|\(primary)|\(secondary ?? "")|\(Int(alpha * 12))"
        if sig == lastSignature { return }
        lastSignature = sig

        let img = buildImage(used: used, remaining: remaining, bob: CGFloat(bob),
                             blink: blink, primary: primary, secondary: secondary, alpha: alpha,
                             sleeping: sleeping, hpUnknown: hpUnknown)
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.image = img
        statusItem.button?.imagePosition = .imageOnly
    }

    func buildImage(used: Int, remaining: Int, bob: CGFloat, blink: Bool,
                    primary: String, secondary: String?, alpha: CGFloat,
                    sleeping: Bool = false, hpUnknown: Bool = false) -> NSImage {
        // When HP is unknown (dozing before any data), the gauge is empty gray.
        let frac: CGFloat = hpUnknown ? 1 : CGFloat(remaining) / 100.0
        // Gauge turns gray while dozing.
        let hpColor = sleeping ? NSColor.systemGray : color(remaining: Double(frac))
        let black = NSColor.black

        let name = "클로드"
        let lv = hpUnknown ? ":Lv--" : ":Lv\(used)"
        let hpLabel = "HP:"
        let hpText = hpUnknown ? "--/100" : "\(remaining)/100"

        let nameAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(15), .foregroundColor: black]
        let lvAttr: [NSAttributedString.Key: Any]   = [.font: pixelFont(12), .foregroundColor: black]
        let hpTextAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(13), .foregroundColor: black]
        let hpLabelAttr: [NSAttributedString.Key: Any] = [.font: pixelFont(10), .foregroundColor: NSColor.systemYellow]
        let slotFont = pixelFont(12)

        let nameSize = (name as NSString).size(withAttributes: nameAttr)
        let lvSize = (lv as NSString).size(withAttributes: lvAttr)
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
        let spriteCols: CGFloat = 15
        let spriteRows: CGFloat = 14
        let cell: CGFloat = 1.28
        let spriteW = spriteCols * cell
        let spriteH = spriteRows * cell

        let hpUnitW = hpLabelSize.width + 8 + 54     // label part + gauge part
        let gaugePartW: CGFloat = 54
        let unitH: CGFloat = 13
        let padX: CGFloat = 7
        let gap: CGFloat = 5
        let spriteNameGap: CGFloat = 9   // 스프라이트 ↔ 이름 간격 (이 숫자를 키우면 더 벌어짐)
        let flavorGap: CGFloat = 10
        let height = NSStatusBar.system.thickness

        let contentW = spriteW + gap + nameSize.width + gap + lvSize.width + gap
            + hpUnitW + gap + hpTextSize.width + flavorGap + slotW
        let totalW = ceil(contentW + padX * 2)

        let img = NSImage(size: NSSize(width: totalW, height: height), flipped: false) { rect in
            // Off-white rounded background pill.
            NSColor(white: 0.90, alpha: 1.0).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 5, yRadius: 5).fill()

            let midY = rect.midY
            var x = padX

            // Sprite (left of the name), with a subtle vertical bob.
            // Unknown HP (dozing pre-data) uses the healthy face so blink = closed eyes.
            let mood = hpUnknown ? .healthy : mood(remaining: remaining)
            let frames = spriteGrids[mood] ?? spriteGrids[.healthy]!
            let grid = (blink && frames.count > 1) ? frames[1] : frames[0]
            let spriteOrigin = NSPoint(x: x, y: midY - spriteH / 2 + bob)
            let colors: [Character: NSColor] = remaining == 0 ? spriteColorsFainted : spriteColors
            drawSprite(grid, origin: spriteOrigin, cell: cell, colors: colors)
            x += spriteW + spriteNameGap   // 스프라이트 ↔ 이름 간격

            func drawText(_ s: String, _ attrs: [NSAttributedString.Key: Any], _ sz: NSSize) {
                (s as NSString).draw(at: NSPoint(x: x, y: midY - sz.height / 2), withAttributes: attrs)
                x += sz.width
            }

            drawText(name, nameAttr, nameSize); x += gap
            drawText(lv, lvAttr, lvSize); x += gap

            // Fused HP unit: single rounded pill, black "HP" cap + white gauge; only inner fill is colored.
            let unit = NSRect(x: x, y: midY - unitH / 2, width: hpUnitW, height: unitH)
            let labelW = hpUnitW - gaugePartW
            let unitPath = NSBezierPath(roundedRect: unit, xRadius: 3, yRadius: 3)
            NSGraphicsContext.current?.saveGraphicsState()
            unitPath.setClip()
            black.setFill(); NSRect(x: unit.minX, y: unit.minY, width: labelW, height: unitH).fill()
            NSColor.white.setFill(); NSRect(x: unit.minX + labelW, y: unit.minY, width: gaugePartW, height: unitH).fill()
            let innerInset: CGFloat = 3
            let innerFull = gaugePartW - innerInset * 2
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
            statusItem.menu = errorMenu("요청이 많아 잠시 쉬는 중이에요.\n곧 자동으로 다시 시도합니다.")
            sleeping = true
            lastSignature = ""
            renderNow()
            return
        }
        sleeping = false

        if let err = result.error {
            hasData = false
            setTitle(text: " C ⚠", color: .systemRed)
            statusItem.menu = errorMenu(err)
            return
        }

        lastLimits = result.limits
        updateDriver(resetCycle: false)
        statusItem.menu = usageMenu(result)
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

    /// Menu action: switch which limit the widget tracks; remember the choice.
    @objc func selectLimit(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String else { return }
        selectedKind = kind
        UserDefaults.standard.set(kind, forKey: "selectedKind")
        updateDriver(resetCycle: true)
        statusItem.menu = usageMenu(last)         // rebuild to move the checkmark
    }

    func usageMenu(_ result: UsageResult) -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "추적할 한도 (✓ 선택됨)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Order: session, weekly_all, then scoped
        let order = ["session", "weekly_all", "weekly_scoped"]
        let sorted = result.limits.sorted {
            (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9)
        }

        for l in sorted {
            let remaining = Double(100 - l.percent) / 100.0
            let bar = batteryBar(remaining: remaining)

            // Clickable row: selects this limit as the tracked one.
            let title = NSMenuItem(title: "\(label(for: l))   \(l.percent)% 사용",
                                   action: #selector(selectLimit(_:)), keyEquivalent: "")
            title.target = self
            title.representedObject = l.kind
            title.state = (l.kind == selectedKind) ? .on : .off   // checkmark
            menu.addItem(title)

            // Bar + reset (informational)
            let barItem = NSMenuItem(title: "", action: #selector(selectLimit(_:)), keyEquivalent: "")
            barItem.target = self
            barItem.representedObject = l.kind
            let s = NSMutableAttributedString(string: "     \(bar)   리셋 \(resetIn(l.resetsAt))")
            s.addAttribute(.font,
                           value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                           range: NSRange(location: 0, length: s.length))
            let barLen = bar.count + 5
            s.addAttribute(.foregroundColor, value: color(remaining: remaining),
                           range: NSRange(location: 0, length: min(barLen, s.length)))
            barItem.attributedTitle = s
            menu.addItem(barItem)

            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(title: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    func errorMenu(_ msg: String) -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "오류: \(msg)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        let hint = NSMenuItem(title: "Claude Code에 로그인돼 있는지 확인하세요", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "다시 시도", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc func refreshNow() { isMocking ? applyMock() : refresh() }

    /// Debug helper: stack sample widgets (varied HP + a mid-crossfade frame) into one PNG.
    func dumpSamples(to path: String) {
        driverResets = Date().addingTimeInterval(3600 + 47 * 60)
        let samples: [(Int, String, String?, CGFloat)] = [
            (5,  "포켓몬센터까지 1시간 47분", nil, 1),       // healthy
            (55, "포켓몬센터까지 32분", nil, 1),            // tired
            (78, "클로드가 울상을 짓고 있다.", nil, 1),   // hurt, flavor showing
            (78, "클로드가 울상을 짓고 있다.", "포켓몬센터까지 12분", 0.5), // mid-crossfade
            (100, "클로드가 쓰러졌다!", nil, 1), // fainted
        ]
        var imgs = samples.map { buildImage(used: $0.0, remaining: 100 - $0.0, bob: 0,
                                            blink: false, primary: $0.1, secondary: $0.2, alpha: $0.3) }
        // dozing WITH prior data (gray bar at last HP)
        imgs.append(buildImage(used: 41, remaining: 59, bob: 0, blink: true,
                               primary: SLEEP_MESSAGE, secondary: nil, alpha: 1, sleeping: true))
        // dozing WITHOUT data (placeholder --/100)
        imgs.append(buildImage(used: 0, remaining: 0, bob: 0, blink: true,
                               primary: SLEEP_MESSAGE, secondary: nil, alpha: 1, sleeping: true, hpUnknown: true))
        let maxW = imgs.map { $0.size.width }.max() ?? 200
        let rowH = NSStatusBar.system.thickness + 4
        let total = NSImage(size: NSSize(width: maxW, height: rowH * CGFloat(imgs.count)), flipped: false) { rect in
            NSColor.darkGray.setFill(); rect.fill()
            var y = rect.height - rowH
            for im in imgs { im.draw(at: NSPoint(x: 2, y: y + 2), from: .zero, operation: .sourceOver, fraction: 1); y -= rowH }
            return true
        }
        let rep = NSBitmapImageRep(data: total.tiffRepresentation!)!
        try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
