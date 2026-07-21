import Cocoa

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
    if frac >= 0.5 { return GB_GREEN }   // match the battle gauge's green
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

