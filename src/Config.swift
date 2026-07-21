import Cocoa

// MARK: - Config

let API_URL = "https://api.anthropic.com/api/oauth/usage"
let OAUTH_BETA = "oauth-2025-04-20"
let KEYCHAIN_SERVICE = "Claude Code-credentials"
let REFRESH_SECONDS: TimeInterval = 240      // 4 min — gentle on the usage endpoint
let MAX_BACKOFF: TimeInterval = 1800         // cap backoff at 30 min
let PIXEL_FONT_NAME = "NeoDunggeunmo"

// Self-update: we poll the GitHub Releases API and swap the .app bundle in place.
// The release tag must be the version with a leading "v" (v1.1 ⇒ VERSION 1.1),
// and the release must carry a ClaudeMonster.zip asset. ./release.sh does both.
let REPO = "wodus1201/ClaudeMonster"
let RELEASES_API = "https://api.github.com/repos/\(REPO)/releases/latest"
let RELEASES_PAGE = "https://github.com/\(REPO)/releases/latest"
let UPDATE_CHECK_INTERVAL: TimeInterval = 6 * 3600   // once every 6 hours

/// This build's version, from Info.plist (injected by build.sh from ./VERSION).
let APP_VERSION = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

/// Sentinel error meaning "no OAuth token in the Keychain" — i.e. Claude Code
/// was never logged in on this Mac. It's the one failure the user can fix, so
/// the menu answers it with instructions instead of a bare error line.
let NO_TOKEN_ERROR = "로그인 토큰 없음"

/// Sentinel error meaning the token exists but the server rejected it (HTTP 401)
/// — the OAuth access token has expired. Claude Code refreshes it whenever it
/// runs, so overnight (CLI unused) the token lapses and this widget sees a 401.
/// Answered with re-auth guidance, same as NO_TOKEN_ERROR.
let EXPIRED_TOKEN_ERROR = "로그인 만료"

// The app was called "ClaudeBattery" before 1.2. These two names are HISTORICAL
// — they identify what an older install left behind, not what we are now — so a
// future rename must not touch them or the cleanup below silently stops working.
let LEGACY_LAUNCH_AGENT_ID = "com.jay.ClaudeBattery"
let LEGACY_PROCESS_NAME = "ClaudeBattery"
