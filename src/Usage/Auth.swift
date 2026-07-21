import Cocoa

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

