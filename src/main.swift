import Cocoa
import CoreText
import ServiceManagement

// ── Claude Monster ─────────────────────────────────────────────────────────
// Personal macOS menu-bar app showing your real Claude usage limits, using the
// same source the IDE extension does: GET /api/oauth/usage with the OAuth token
// Claude Code already stored in the macOS Keychain. No external deps.
// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
