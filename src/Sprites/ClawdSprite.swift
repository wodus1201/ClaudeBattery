import Cocoa

// MARK: - Claude pixel sprite

enum Mood { case healthy, tired, hurt, fainted, happy }

func mood(remaining: Int) -> Mood {
    if remaining >= 50 { return .healthy }   // green
    if remaining >= 20 { return .tired }     // orange
    if remaining >= 1  { return .hurt }      // red
    return .fainted                          // 0
}

let spriteColors: [Character: NSColor] = [
    "B": NSColor(srgbRed: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1),  // Claude orange
    "D": NSColor(srgbRed: 0xA6/255, green: 0x47/255, blue: 0x2E/255, alpha: 1),  // dark outline
    "K": NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),              // near-black
    "W": NSColor.white,
    "T": NSColor(srgbRed: 0x4F/255, green: 0xA3/255, blue: 0xE3/255, alpha: 1),  // tear/sweat
    "M": NSColor(srgbRed: 0x5A/255, green: 0x22/255, blue: 0x22/255, alpha: 1),  // mouth
]

let spriteColorsFainted: [Character: NSColor] = [
    "B": NSColor(calibratedWhite: 0.72, alpha: 1),
    "D": NSColor(calibratedWhite: 0.45, alpha: 1),
    "K": NSColor(calibratedWhite: 0.15, alpha: 1),
    "W": NSColor.white,
    "T": NSColor(calibratedWhite: 0.70, alpha: 1),
    "M": NSColor(calibratedWhite: 0.30, alpha: 1),
]

// MARK: - Claude skins (color customization)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
}

/// A recolor of Claude. The sprite grids never change — only these three body
/// tones do — so one skin applies identically to the menu-bar widget and the
/// battle screen. `unlockPets > 0` gates a skin behind a petting count (the
/// shiny), keeping it hidden until Claude has been petted that many times.
struct ClawdSkin {
    let id: String
    let name: String
    let highlight: NSColor   // battle shading 'L'
    let base: NSColor        // body 'B'
    let shadow: NSColor      // outline/shadow 'D'
    var unlockPets: Int = 0
    /// Overrides the derived outline. Only the shiny sets this — a gold keyline is
    /// how it stays distinguishable when nothing is moving, since the sparkle
    /// (below) is transient and the ★ is easy to overlook.
    var outlineOverride: NSColor? = nil

    /// The shiny is the only skin with an unlock gate, and everything that marks
    /// it as rare keys off this rather than off a literal "shiny" id, so a second
    /// gated skin would inherit the whole treatment for free.
    var isRare: Bool { unlockPets > 0 }

    /// Widget sprite is 2-tone (B/D) over fixed face details (K/W/T/M).
    var widgetColors: [Character: NSColor] {
        var c = spriteColors
        c["B"] = base
        c["D"] = shadow
        return c
    }
    /// The outline, as a deepened version of the skin's own shadow rather than
    /// black: a hard black keyline reads as a sticker pasted onto the scene, and
    /// the widget already outlines Claude in dark orange ('D' in spriteColors).
    /// Derived, not hand-picked, so every skin — and any skin added later — gets
    /// an outline that matches its body instead of one more color to keep in sync.
    var outline: NSColor {
        if let o = outlineOverride { return o }
        let c = shadow.usingColorSpace(.sRGB) ?? shadow
        return NSColor(srgbRed: c.redComponent * 0.55,
                       green: c.greenComponent * 0.55,
                       blue: c.blueComponent * 0.55, alpha: 1)
    }
    /// Battle sprite is shaded into three tones (L/B/D) over that tinted outline.
    var battleColors: [Character: NSColor] {
        ["K": outline, "L": highlight, "B": base, "D": shadow]
    }
}

/// How many pets unlock the shiny.
let PETS_TO_SHINY = 50

/// Six variants, to fill a Pokémon-style party screen: the default and the four
/// model themes, then the shiny last — it is the rare one, so it sits at the end
/// of the party (bottom-right of the 2x3 picker) rather than beside the default.
/// Colors are original recolors of our own sprite, not from any existing game.
let ALL_SKINS: [ClawdSkin] = [
    ClawdSkin(id: "default", name: "클로드",
              highlight: rgb(0xF5,0xB8,0x95), base: rgb(0xD9,0x77,0x57), shadow: rgb(0xA6,0x47,0x2E)),
    ClawdSkin(id: "opus", name: "오퍼스",
              highlight: rgb(0xCF,0xAC,0xF0), base: rgb(0x88,0x58,0xB0), shadow: rgb(0x57,0x30,0x80)),
    ClawdSkin(id: "sonnet", name: "소네트",
              highlight: rgb(0x9E,0xD0,0xF8), base: rgb(0x4A,0x82,0xC8), shadow: rgb(0x2C,0x54,0x90)),
    ClawdSkin(id: "haiku", name: "하이쿠",
              highlight: rgb(0xB4,0xEE,0xB0), base: rgb(0x58,0xB0,0x5A), shadow: rgb(0x30,0x80,0x36)),
    ClawdSkin(id: "fable", name: "페이블",
              highlight: rgb(0xFA,0xC2,0xE0), base: rgb(0xD8,0x60,0xA0), shadow: rgb(0xA0,0x38,0x70)),
    ClawdSkin(id: "shiny", name: "이로치",
              highlight: rgb(0xFC,0xF0,0xC0), base: rgb(0xF0,0xC2,0x52), shadow: rgb(0xBE,0x86,0x2E),
              unlockPets: PETS_TO_SHINY,
              outlineOverride: rgb(0x6B,0x45,0x0E)),   // warm gold-brown, not the derived near-black
]

func skin(id: String) -> ClawdSkin { ALL_SKINS.first { $0.id == id } ?? ALL_SKINS[0] }

// Official-style Clawd: 20 cols x 14 rows. The body/ears/arms/legs are constant;
// only the two eye rows (index 5,6) change per mood. Row 0 = top.
let clawdBase: [String] = [
    ".....DBBBBBBBBD.....",
    "....DBDBBBBBBDBD....",
    "..DBBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBBD..",   // eyes row (5) — replaced per mood
    "..DBBBBBBBBBBBBBBD..",   // eyes row (6) — replaced per mood
    "DDBBBBBBBBBBBBBBBBDD",   // arms
    "DDBBBBBBBBBBBBBBBBDD",   // arms
    "..DBBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBBD..",
    "..DBBBBBBBBBBBBBBD..",
    "...DB..BD..BD..BD...",
    "...DB..BD..BD..BD...",
]

func makeFace(_ eyeRow5: String, _ eyeRow6: String) -> [String] {
    var g = clawdBase
    g[5] = eyeRow5
    g[6] = eyeRow6
    return g
}

// Row 0 = top. Frames per mood; index 1 (if present) is a brief blink.
let spriteGrids: [Mood: [[String]]] = [
    // content: open eyes; blink: eyes closed
    .healthy: [
        makeFace("..DBBBKKBBBBKKBBBD..", "..DBBBKKBBBBKKBBBD.."),
        makeFace("..DBBBBBBBBBBBBBBD..", "..DBBBKKBBBBKKBBBD.."),
    ],
    // tired: half-lidded (single row) + sweat drop at top-right
    .tired: [
        makeFace("..DBBKKKBBBBKKKBBD..", "..DBBBKKBBBBKKBBBD.."),
        makeFace("..DBBBBBBBBBBBBBBD..", "..DBBKKKBBBBKKKBBD.."),
    ],
    // hurt: wide worried eyes + teardrop
    .hurt: [
        makeFace("..DBBBKKBBBBKKBBBD..", "..DBTTKKBBBBKKTTBD.."),
        makeFace("..DBBBBBBBBBBBBBBD..", "..DBTTKKBBBBKKTTBD.."),
    ],
    // fainted: X-shaped eyes
    .fainted: [
        makeFace("..DBBBBBBBBBBBBBBD..", "..DBBKKKBBBBKKKBBD.."),
    ],
    // happy (sprite clicked): upturned "^ ^" eyes. Single frame — no blink, so
    // the smile holds steady for the whole petting window.
    .happy: [
        makeFace("..DBBBBKBBBBKBBBBD..", "..DBBBKBKBBKBKBBBD.."),
    ],
]

/// Draw a pixel grid with crisp (non-antialiased) cells; row 0 is the top.
func drawSprite(_ grid: [String], origin: NSPoint, cell: CGFloat, colors: [Character: NSColor] = spriteColors) {
    guard let ctx = NSGraphicsContext.current else { return }
    ctx.saveGraphicsState()
    ctx.shouldAntialias = false
    let rows = grid.count
    for (r, line) in grid.enumerated() {
        for (c, ch) in line.enumerated() {
            guard let color = colors[ch] else { continue }
            color.setFill()
            let x = origin.x + CGFloat(c) * cell
            let y = origin.y + CGFloat(rows - 1 - r) * cell   // flip vertically
            NSRect(x: x, y: y, width: cell, height: cell).fill()
        }
    }
    ctx.restoreGraphicsState()
}
