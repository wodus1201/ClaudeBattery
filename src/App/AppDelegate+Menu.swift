import Cocoa

extension AppDelegate {
    // MARK: - Click routing

    /// Clicking the sprite pets Claude. A left-click elsewhere drops down the
    /// battle screen; a right-click still opens the plain menu — that menu is
    /// the only way to quit, so it must stay reachable even if the panel breaks.
    @objc func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // sendAction(on:) synthesizes the event, so locationInWindow is the
        // button's center, not the mouse. Ask the system where the cursor is.
        let inSprite: Bool = {
            guard let win = sender.window else { return false }
            let screenP = NSEvent.mouseLocation
            let winP = win.convertPoint(fromScreen: screenP)
            let p = sender.convert(winP, from: nil)
            // spriteHitMaxX is in image coordinates; .imageOnly centers the
            // image in the button, so shift by the leftover margin.
            let originX = (sender.bounds.width - (sender.image?.size.width ?? sender.bounds.width)) / 2
            return p.x >= originX && p.x - originX <= spriteHitMaxX
        }()
        let isRightClick = event.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false

        // Petting needs a face to react with; while dozing or error, just menu.
        if inSprite && hasData && !sleeping {
            pet()
        } else if isRightClick || !hasData || sleeping {
            // No data means no HP to draw, so fall back to the menu, which also
            // explains *why* (login needed / rate-limited).
            popUpMenu(sender)
        } else {
            toggleBattlePanel(sender)
        }
    }

    func popUpMenu(_ sender: NSStatusBarButton) {
        guard let menu = currentMenu else { return }
        statusItem.menu = menu          // attach, pop up, then detach so the
        sender.performClick(nil)        // next plain click reaches us again
        statusItem.menu = nil
    }

    func selectLimit(kind: String) {
        selectedKind = kind
        UserDefaults.standard.set(kind, forKey: "selectedKind")
        updateDriver(resetCycle: true)
        rebuildMenu()                             // rebuild to move the checkmark
    }

    /// Menu action: switch which limit the widget tracks.
    @objc func selectLimitFromMenu(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String else { return }
        selectLimit(kind: kind)
    }

    /// Rebuild `currentMenu` from the latest result. Anything that changes what
    /// the menu shows — a new limit selection, an available update, the
    /// launch-at-login state — funnels through here so all three menu shapes
    /// (usage / dozing / error) stay in sync.
    func rebuildMenu() {
        if last.rateLimited {
            currentMenu = errorMenu("요청이 많아 잠시 쉬는 중이에요.\n곧 자동으로 다시 시도합니다.",
                                    showCompactToggle: true)
        } else if let err = last.error {
            currentMenu = errorMenu(err)
        } else {
            currentMenu = usageMenu(last)
        }
    }

    /// Items shared by every menu shape: update status, launch-at-login, quit.
    func appendCommonItems(to menu: NSMenu) {
        menu.addItem(.separator())

        if isUpdating {
            let item = NSMenuItem(title: "업데이트 설치 중…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let up = availableUpdate {
            let item = NSMenuItem(title: "🎁 새 버전 \(up.version) 설치",
                                  action: #selector(installUpdateNow), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "업데이트 확인 (v\(APP_VERSION))",
                                  action: #selector(checkForUpdateNow), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let login = NSMenuItem(title: "로그인 시 자동 시작",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
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
                                   action: #selector(selectLimitFromMenu(_:)), keyEquivalent: "")
            title.target = self
            title.representedObject = l.kind
            title.state = (l.kind == selectedKind) ? .on : .off   // checkmark
            menu.addItem(title)

            // Bar + reset (informational)
            let barItem = NSMenuItem(title: "", action: #selector(selectLimitFromMenu(_:)), keyEquivalent: "")
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

        let compactItem = NSMenuItem(title: "좁게 보기 (메뉴바 폭 줄이기)",
                                     action: #selector(toggleCompact), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = compact ? .on : .off
        menu.addItem(compactItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "지금 새로고침", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        appendCommonItems(to: menu)
        return menu
    }

    /// Menu action: toggle compact mode (hides Lv, shrinks the dialogue font)
    /// so the widget fits menu bars with limited space; choice persists.
    @objc func toggleCompact() {
        compact.toggle()
        UserDefaults.standard.set(compact, forKey: "compact")
        lastSignature = ""
        renderNow()
        rebuildMenu()                       // rebuild to move the checkmark
    }

    func errorMenu(_ msg: String, showCompactToggle: Bool = false) -> NSMenu {
        let menu = NSMenu()

        if msg == NO_TOKEN_ERROR {
            // Not really an error from the user's side — they just haven't logged
            // in yet. Say what to do, and offer the how.
            let item = NSMenuItem(title: "Claude Code에 로그인이 필요합니다", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let how = NSMenuItem(title: "로그인하는 방법 보기…",
                                 action: #selector(showLoginHelp), keyEquivalent: "")
            how.target = self
            menu.addItem(how)
        } else if msg == EXPIRED_TOKEN_ERROR {
            // Token lapsed. Running Claude Code once refreshes it; say so.
            let item = NSMenuItem(title: "로그인이 만료됐습니다", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let how = NSMenuItem(title: "갱신하는 방법 보기…",
                                 action: #selector(showReauthHelp), keyEquivalent: "")
            how.target = self
            menu.addItem(how)
        } else {
            let item = NSMenuItem(title: "오류: \(msg)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let hint = NSMenuItem(title: "Claude Code에 로그인돼 있는지 확인하세요", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        if showCompactToggle {
            let compactItem = NSMenuItem(title: "좁게 보기 (메뉴바 폭 줄이기)",
                                         action: #selector(toggleCompact), keyEquivalent: "")
            compactItem.target = self
            compactItem.state = compact ? .on : .off
            menu.addItem(compactItem)
            menu.addItem(.separator())
        }
        let refreshItem = NSMenuItem(title: "다시 시도", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        appendCommonItems(to: menu)
        return menu
    }

    @objc func refreshNow() { isMocking ? applyMock() : refresh() }

    /// Render the app icon from the same pixel grid the widget uses, so the icon
    /// can never drift from the sprite. make-icon.sh turns this into a .icns.
}
