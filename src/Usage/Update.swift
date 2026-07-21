import Cocoa

// MARK: - Self-update

/// Compare dotted versions numerically: "1.10" is newer than "1.9",
/// which a plain string compare would get backwards.
func isNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
    let a = parts(candidate), b = parts(current)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0
        let y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

struct Release {
    let version: String   // tag without the leading "v"
    let zipURL: URL
}

/// Ask GitHub for the latest release. Returns nil on any failure — a missing
/// network or a rate-limited API must never disturb the widget.
func fetchLatestRelease(completion: @escaping (Release?) -> Void) {
    guard let url = URL(string: RELEASES_API) else { completion(nil); return }
    var req = URLRequest(url: url)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.timeoutInterval = 10

    URLSession.shared.dataTask(with: req) { data, resp, _ in
        guard let data = data,
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]]
        else { completion(nil); return }

        // The .app is shipped as a zip asset; without it there's nothing to install.
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        guard let urlStr = zip?["browser_download_url"] as? String,
              let zipURL = URL(string: urlStr)
        else { completion(nil); return }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        completion(Release(version: version, zipURL: zipURL))
    }.resume()
}

enum UpdateError: LocalizedError {
    case download(String), unpack, noBundle, notWritable(String), devBuild
    var errorDescription: String? {
        switch self {
        case .download(let m): return "다운로드 실패: \(m)"
        case .unpack:          return "압축 해제 실패"
        case .noBundle:        return "새 앱을 찾을 수 없습니다"
        case .notWritable(let p): return "쓰기 권한 없음: \(p)"
        case .devBuild:
            return "개발 빌드(build/)는 자동 업데이트를 지원하지 않습니다.\n"
                 + "소스에서는 git pull && ./build.sh 를 사용하세요."
        }
    }
}

/// Download the release zip, unpack it, then hand off to a detached script that
/// swaps the bundle and relaunches. We cannot overwrite our own bundle while
/// running, so the script waits for this process to exit first.
func installUpdate(_ release: Release, completion: @escaping (Error?) -> Void) {
    // The running bundle may be reached via the /Applications symlink that
    // install.sh creates; resolve it so we replace the real directory.
    let installedApp = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let parent = installedApp.deletingLastPathComponent()

    // Resolving that symlink can land us inside the source checkout's build/
    // directory. Overwriting a build artifact with a release zip would just
    // confuse the next ./build.sh, so refuse and point at the git workflow.
    guard parent.lastPathComponent != "build" else {
        completion(UpdateError.devBuild); return
    }
    guard FileManager.default.isWritableFile(atPath: parent.path) else {
        completion(UpdateError.notWritable(parent.path)); return
    }

    URLSession.shared.downloadTask(with: release.zipURL) { tmp, _, err in
        if let err = err { completion(UpdateError.download(err.localizedDescription)); return }
        guard let tmp = tmp else { completion(UpdateError.download("빈 응답")); return }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ClaudeMonsterUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: tmp, to: zip)

            // ditto preserves the bundle's symlinks and signature layout; unzip does not.
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { completion(UpdateError.unpack); return }

            // Find the .app the archive contains (name may differ from ours).
            let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "app" }
            guard let newApp = newApp else { completion(UpdateError.noBundle); return }

            try writeAndRunSwapScript(newApp: newApp, installedApp: installedApp, work: work)
            completion(nil)   // caller quits; the script takes over from here
        } catch {
            completion(error)
        }
    }.resume()
}

/// Write a detached script that waits for us to quit, swaps the bundle, and
/// relaunches. Detaching matters: it must outlive the process it replaces.
private func writeAndRunSwapScript(newApp: URL, installedApp: URL, work: URL) throws {
    let script = work.appendingPathComponent("swap.sh")
    // Wait on *our* process name rather than a hardcoded one, so a future
    // rename can't leave the script watching for a process that never exits.
    let proc = ProcessInfo.processInfo.processName
    let body = """
    #!/bin/bash
    # Wait (up to ~10s) for the running app to exit before touching its bundle.
    for _ in $(seq 1 100); do
      pgrep -x \(proc) >/dev/null || break
      sleep 0.1
    done
    pkill -x \(proc) 2>/dev/null || true
    sleep 0.3

    # Keep the old bundle until the new one is in place, so a failure is recoverable.
    BACKUP="\(installedApp.path).bak"
    rm -rf "$BACKUP"
    mv "\(installedApp.path)" "$BACKUP" 2>/dev/null || true
    if ! mv "\(newApp.path)" "\(installedApp.path)"; then
      mv "$BACKUP" "\(installedApp.path)" 2>/dev/null || true   # roll back
      rm -rf "\(work.path)"
      exit 1
    fi
    rm -rf "$BACKUP"

    # Re-sign ad-hoc: the zip round-trip and mv can invalidate the signature.
    codesign --force --sign - "\(installedApp.path)" 2>/dev/null || true
    xattr -dr com.apple.quarantine "\(installedApp.path)" 2>/dev/null || true

    open "\(installedApp.path)"
    rm -rf "\(work.path)"
    """
    try body.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script.path]
    try p.run()   // detached: we exit right after, it keeps going
}

