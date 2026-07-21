import Cocoa
import ServiceManagement

extension AppDelegate {
    // MARK: - Self-update

    /// Check shortly after launch, then every UPDATE_CHECK_INTERVAL.
    func scheduleUpdateChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdate(userInitiated: false)
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: UPDATE_CHECK_INTERVAL,
                                           repeats: true) { [weak self] _ in
            self?.checkForUpdate(userInitiated: false)
        }
    }

    /// A background check only annotates the menu; a user-initiated one always
    /// reports back, including "you're already up to date".
    func checkForUpdate(userInitiated: Bool) {
        fetchLatestRelease { [weak self] release in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let newer = release.map { isNewer($0.version, than: APP_VERSION) } ?? false
                self.availableUpdate = newer ? release : nil
                self.rebuildMenu()

                guard userInitiated else { return }
                if release == nil {
                    self.alert("업데이트 확인 실패", "네트워크 상태를 확인해 주세요.")
                } else if !newer {
                    self.alert("최신 버전입니다", "현재 버전 \(APP_VERSION)")
                } else {
                    // A hand-triggered check needs an answer on the spot. Rebuilding
                    // the menu adds the 🎁 item, but the menu the user just clicked
                    // is already drawn, so silently doing nothing reads as a no-op.
                    self.installUpdateNow()
                }
            }
        }
    }

    /// Menu action: download + swap + relaunch, with a confirmation first.
    @objc func installUpdateNow() {
        guard let release = availableUpdate, !isUpdating else { return }

        let a = NSAlert()
        a.messageText = "새 버전 \(release.version) 설치"
        a.informativeText = "다운로드 후 앱이 자동으로 재시작됩니다."
        a.addButton(withTitle: "설치")
        a.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        isUpdating = true
        rebuildMenu()
        installUpdate(release) { [weak self] err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let err = err {
                    self.isUpdating = false
                    self.rebuildMenu()
                    self.alert("업데이트 실패", err.localizedDescription)
                } else {
                    // The swap script is waiting for us to exit.
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Menu action: user asked to check right now.
    @objc func checkForUpdateNow() { checkForUpdate(userInitiated: true) }

    func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - First-run onboarding

    /// The widget lives only in the menu bar, so a first-time user gets no signal
    /// that anything launched — and no hint that the two things it needs (a Claude
    /// Code login, and auto-start) are opt-in. Say so once, then never again.
    func showWelcomeIfFirstRun() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let a = NSAlert()
        a.messageText = "Claude Monster에 오신 걸 환영합니다!"
        a.informativeText = """
            메뉴바 오른쪽에 클로드가 나타났습니다. 남은 사용 한도를 HP로 보여주고, \
            클로드를 클릭하면 쓰다듬을 수 있어요.

            시작하려면 이 맥에서 Claude Code에 로그인돼 있어야 합니다. \
            (터미널에서 claude 를 실행해 로그인하세요.)

            로그인이 돼 있다면 곧 Keychain 접근을 물어봅니다 — "항상 허용"을 눌러주세요.
            """
        a.addButton(withTitle: "로그인 시 자동 시작 켜기")
        a.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)

        if a.runModal() == .alertFirstButtonReturn, !launchAtLogin {
            do { try SMAppService.mainApp.register() }
            catch { alert("자동 시작 설정 실패", error.localizedDescription) }
            rebuildMenu()
        }
    }

    /// Menu action: shown when the Keychain has no Claude Code token.
    @objc func showLoginHelp() {
        let a = NSAlert()
        a.messageText = "Claude Code에 로그인하세요"
        a.informativeText = """
            이 위젯은 Claude Code가 Keychain에 저장해 둔 로그인 토큰을 읽어 \
            사용 한도를 가져옵니다. 토큰을 외부로 보내지 않습니다.

            1. 터미널을 엽니다
            2. claude 를 실행하고 안내에 따라 로그인합니다
            3. 이 메뉴에서 "다시 시도"를 누릅니다

            Claude Code가 설치돼 있지 않다면 claude.com/claude-code 를 참고하세요.
            """
        a.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Menu action: shown on a 401 — the token expired and needs refreshing.
    @objc func showReauthHelp() {
        let a = NSAlert()
        a.messageText = "로그인이 만료됐어요"
        a.informativeText = """
            Claude Code 로그인 토큰은 약 8시간마다 만료되고, Claude Code를 \
            실행하면 자동으로 갱신됩니다. 밤새 Claude Code를 쓰지 않으면 토큰이 \
            만료돼 이 위젯에 401 오류가 뜰 수 있어요.

            갱신하려면:
            1. 터미널에서 claude 를 한 번 실행합니다 (로그인돼 있으면 자동 갱신됨)
            2. 이 메뉴에서 "다시 시도"를 누릅니다
            """
        a.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - Launch at login

    /// Whether macOS currently launches us at login (SMAppService, macOS 13+).
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    @objc func toggleLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() }
            else             { try SMAppService.mainApp.register() }
        } catch {
            alert("자동 시작 설정 실패", error.localizedDescription)
        }
        rebuildMenu()
    }

    /// UserDefaults are keyed by bundle ID, so the 1.2 rename orphaned the old
    /// app's preferences. Carry them over once rather than silently resetting
    /// the user's compact-mode and tracked-limit choices.
    func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        let key = "didMigrateLegacyPrefs"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        guard let old = UserDefaults(suiteName: LEGACY_LAUNCH_AGENT_ID) else { return }
        if let kind = old.string(forKey: "selectedKind") {
            defaults.set(kind, forKey: "selectedKind")
            selectedKind = kind
        }
        if let compactPref = old.object(forKey: "compact") as? Bool {
            defaults.set(compactPref, forKey: "compact")
            compact = compactPref
        }
    }

    /// Retire what a pre-1.2 "ClaudeBattery" install left behind: a LaunchAgent
    /// that starts the old binary, and possibly that binary still running. Both
    /// would sit alongside us — the agent fights SMAppService, and the old
    /// process puts a second widget in the menu bar.
    func retireLegacyInstall() {
        // Kill a still-running old build first; it has a different executable
        // name, so nothing else would ever reap it.
        if Bundle.main.executableURL?.lastPathComponent != LEGACY_PROCESS_NAME {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            kill.arguments = ["-x", LEGACY_PROCESS_NAME]
            try? kill.run()
            kill.waitUntilExit()
        }

        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LEGACY_LAUNCH_AGENT_ID).plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { return }

        let uid = getuid()
        let boot = Process()
        boot.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        boot.arguments = ["bootout", "gui/\(uid)/\(LEGACY_LAUNCH_AGENT_ID)"]
        try? boot.run()
        boot.waitUntilExit()
        try? FileManager.default.removeItem(at: plist)

        // The plist existed, so auto-start was wanted. Re-express that through
        // SMAppService, which the menu toggle now owns. Only meaningful for an
        // installed bundle; a build/ copy would register the wrong path.
        let parent = Bundle.main.bundleURL.resolvingSymlinksInPath()
            .deletingLastPathComponent().lastPathComponent
        if parent != "build", !launchAtLogin {
            try? SMAppService.mainApp.register()
        }
    }

    /// Feeds fixture data through the exact same `apply()` path real data uses,
    /// so the live menu-bar widget, animations, and click-to-switch menu all
    /// work normally — with zero network calls (apply() skips scheduleNext()
    /// while isMocking, so no timer ever fires a real fetchUsage()).
}
