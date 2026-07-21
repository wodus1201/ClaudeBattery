import Cocoa

extension AppDelegate {
    // MARK: - Battle panel

    func toggleBattlePanel(_ sender: NSStatusBarButton) {
        if battlePanel != nil { closeBattlePanel(); return }
        // If the global monitor just closed the panel from this very click, don't
        // reopen — clicking the status item while open should close, not re-toggle.
        if let t = battleClosedAt, Date().timeIntervalSince(t) < 0.3 { return }
        openBattlePanel(sender)
    }

    func openBattlePanel(_ button: NSStatusBarButton) {
        let view = BattleView(frame: NSRect(x: 0, y: 0, width: BATTLE_W, height: BATTLE_H),
                              usedPercent: driverUsed ?? 0, limits: lastLimits,
                              selectedKind: selectedKind, compactOn: compact,
                              skinID: selectedSkinID, petCount: petCount)
        view.perform = { [weak self, weak view] action in
            self?.runBattleAction(action, from: view)
        }
        view.onDismiss = { [weak self] in self?.closeBattlePanel() }

        let panel = BattlePanel(contentRect: view.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = view

        // Sit under the status item, clamped into the screen on both axes — a
        // short screen would otherwise cut the panel's bottom off.
        var origin = NSPoint.zero
        if let win = button.window {
            let f = win.frame
            var x = f.midX - BATTLE_W / 2
            var y = f.minY - BATTLE_H - 4
            if let vis = (win.screen ?? NSScreen.main)?.visibleFrame {
                x = min(max(x, vis.minX + 8), vis.maxX - BATTLE_W - 8)
                y = max(y, vis.minY + 8)
                y = min(y, vis.maxY - BATTLE_H - 4)
            }
            origin = NSPoint(x: x, y: y)
        }

        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y + 8))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(view)      // or arrow keys / Enter never reach it
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(origin)
            panel.animator().alphaValue = 1
        }
        battlePanel = panel

        // NSPopover's .transient, by hand. Esc is handled inside the view, which
        // steps back a page before dismissing (via onDismiss at the root).
        battleMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeBattlePanel()
        }
    }

    /// Run a battle-menu action. Anything that changes tracked state goes through
    /// the same methods the right-click menu uses, so the widget and the panel
    /// can never disagree; afterwards the panel is refreshed from the new state.
    func runBattleAction(_ action: BattleAction, from view: BattleView?) {
        switch action {
        case .pickLimit(let kind):
            selectLimit(kind: kind)          // redraws the widget (Lv + HP)
            refreshBattleView(view)
        case .pickSkin(let id):
            selectSkin(id: id)               // recolors the widget
            refreshBattleView(view)
            view?.go(to: .root)              // back out of the picker after choosing
        case .toggleCompact:
            toggleCompact()                  // redraws the widget
            refreshBattleView(view)
        case .checkUpdate:
            // The alert is modal; the panel would hang behind it, so dismiss first.
            closeBattlePanel()
            checkForUpdate(userInitiated: true)
        case .refresh:
            // Fetching is async, so the panel can only be refreshed once apply()
            // has landed the new numbers — hence the delay rather than an
            // immediate refreshBattleView(), which would redraw the old data.
            refreshNow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak view] in
                self?.refreshBattleView(view)
            }
        case .quit:
            closeBattlePanel()
            NSApp.terminate(nil)
        case .openUsage, .openMore, .openSkins, .openBattle, .tackle, .back, .none:
            break                            // handled inside the view
        }
    }

    /// Switch the Claude skin; remember it. Redraws the widget immediately.
    func selectSkin(id: String) {
        selectedSkinID = id
        UserDefaults.standard.set(id, forKey: "clawdSkin")
        lastSignature = ""       // force the widget to repaint in the new color
        renderNow()
    }

    /// Push the delegate's current state back into the open panel.
    private func refreshBattleView(_ view: BattleView?) {
        guard let view = view else { return }
        let wasShiny = view.isShiny
        view.usedPercent = driverUsed ?? 0
        view.limits = lastLimits
        view.selectedKind = selectedKind
        view.compactOn = compact
        view.skinID = selectedSkinID
        view.petCount = petCount
        // Switching *into* the shiny replays the burst — that pick is the payoff
        // for 50 pets. Only on the transition, or every refresh would re-fire it.
        if !wasShiny && view.isShiny { view.startSparkle() }
        view.needsDisplay = true
    }

    func closeBattlePanel() {
        if let m = battleMonitor { NSEvent.removeMonitor(m); battleMonitor = nil }
        guard let panel = battlePanel else { return }
        // Clear the reference first: the animation outlives this call, and a
        // click landing mid-fade would otherwise toggle against a dying panel.
        battlePanel = nil
        battleClosedAt = Date()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Show the happy face + an affection line for PETTING_HOLD seconds. Each pet
    /// counts toward unlocking the shiny skin; the count persists.
    func pet() {
        let remaining = max(0, min(100, 100 - (driverUsed ?? 0)))
        let m = mood(remaining: remaining)
        // The shiny gets its own reactions — but a fainted Claude stays fainted,
        // so the somber lines still win. Rarity does not outrank 0 HP.
        var pool = (currentSkin.isRare && m != .fainted)
            ? shinyPettingLines()
            : pettingLines(mood: m)
        if pool.count > 1 { pool.removeAll { $0 == lastPettingLine } }
        let line = pool.randomElement() ?? lastPettingLine
        lastPettingLine = line
        pettingLine = line
        pettingUntil = Date().addingTimeInterval(PETTING_HOLD)
        lastSignature = ""      // force an immediate redraw
        renderNow()

        let wasLocked = petCount < PETS_TO_SHINY
        petCount += 1
        UserDefaults.standard.set(petCount, forKey: "petCount")
        if wasLocked && petCount >= PETS_TO_SHINY {
            // Cross the threshold exactly once — tell the user the shiny appeared.
            DispatchQueue.main.asyncAfter(deadline: .now() + PETTING_HOLD) { [weak self] in
                self?.alert("이로치 클로드 해금!",
                            "정성껏 쓰다듬어 줬네요. '색상 커스텀'에서 이로치 클로드를 고를 수 있어요.")
            }
        }
    }

    /// Switch which limit the widget tracks; remember the choice. Shared by the
    /// right-click menu and the battle screen, so both stay in step — the widget
    /// redraws either way.
}
