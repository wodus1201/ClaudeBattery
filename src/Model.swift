import Cocoa

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
