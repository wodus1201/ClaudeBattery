import Cocoa

extension AppDelegate {
    func writeIconPNG(to path: String) {
        let side: CGFloat = 1024
        let grid = spriteGrids[.happy]![0]     // the smiling face reads best small
        let cols = CGFloat(grid[0].count), rows = CGFloat(grid.count)

        // Fit the sprite into ~66% of the canvas, keeping pixels square, then
        // center it. macOS icons want visible breathing room at the edges.
        let cell = (side * 0.66 / max(cols, rows)).rounded(.down)
        let w = cols * cell, h = rows * cell

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // Rounded-square backdrop in Claude's cream, matching the widget pill.
            let inset = rect.insetBy(dx: side * 0.06, dy: side * 0.06)
            NSColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1).setFill()
            NSBezierPath(roundedRect: inset, xRadius: side * 0.18, yRadius: side * 0.18).fill()

            drawSprite(grid,
                       origin: NSPoint(x: (side - w) / 2, y: (side - h) / 2),
                       cell: cell)
            return true
        }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Debug helper: render the battle panel offscreen so its design can be
    /// inspected without opening a window or touching the network.
    func dumpBattle(to path: String, usedPercent: Int) {
        let now = Date()
        let fixture = [
            Limit(kind: "session", percent: usedPercent,
                  resetsAt: now.addingTimeInterval(3600 * 2), scopeName: nil, isActive: true),
            Limit(kind: "weekly_all", percent: 55,
                  resetsAt: now.addingTimeInterval(86400 * 3), scopeName: nil, isActive: false),
            Limit(kind: "weekly_scoped", percent: 0,
                  resetsAt: nil, scopeName: "Fable", isActive: false),
        ]
        // All menu pages, stacked, so a design change can be checked at once.
        // The skin picker is shown with the shiny unlocked so its cell renders.
        // CLAUDEMONSTER_ONEPAGE=1 dumps only the root page, so indicator tweaks can
        // be zoomed without the tall five-page stack.
        let pages: [BattleScreen] = ProcessInfo.processInfo.environment["CLAUDEMONSTER_ONEPAGE"] != nil
            ? [.root]
            : [.root, .battle, .usage, .more, .skins]
        let gap: CGFloat = 10
        let size = NSSize(width: BATTLE_W, height: (BATTLE_H + gap) * CGFloat(pages.count) - gap)
        let img = NSImage(size: size, flipped: false) { rect in
            // cacheDisplay leaves everything outside the rounded panel transparent,
            // which a PNG viewer paints white — that reads as a rendering bug when
            // the live panel is simply see-through. Lay down a backdrop first.
            NSColor(white: 0.25, alpha: 1).setFill(); rect.fill()
            var y = size.height - BATTLE_H
            for page in pages {
                // CLAUDEMONSTER_SKIN=<id> dumps the panel wearing that skin, so the
                // shiny's gold outline and ★ can be checked without 50 real pets.
                let dumpSkin = ProcessInfo.processInfo.environment["CLAUDEMONSTER_SKIN"] ?? "default"
                let view = BattleView(frame: NSRect(x: 0, y: 0, width: BATTLE_W, height: BATTLE_H),
                                      usedPercent: usedPercent, limits: fixture,
                                      selectedKind: "session", compactOn: true,
                                      skinID: dumpSkin, petCount: PETS_TO_SHINY)
                view.go(to: page)
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    rep.draw(in: NSRect(x: 0, y: y, width: BATTLE_W, height: BATTLE_H))
                }
                y -= BATTLE_H + gap
            }
            return true
        }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

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
        // petting: healthy Claude smiles
        imgs.append(buildImage(used: 5, remaining: 95, bob: 0, blink: false,
                               primary: "클로드가 기뻐서 빙글빙글 돈다!", secondary: nil, alpha: 1,
                               petting: true))
        // petting: fainted Claude stays fainted (no smile)
        imgs.append(buildImage(used: 100, remaining: 0, bob: 0, blink: false,
                               primary: "클로드는 쓰러져서 반응이 없다..", secondary: nil, alpha: 1,
                               petting: true))
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
