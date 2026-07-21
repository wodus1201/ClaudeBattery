import Cocoa

// MARK: - Battle screen (click-to-open panel)
//
// Clicking the widget drops down a Pokémon-style battle screen. It is a
// borderless NSPanel, not an NSPopover: a popover forces an arrow and the
// system's translucent material, neither of which can be removed, and both
// clash with the pixel art. The cost is that "click outside to dismiss" —
// free with popovers — has to be built by hand (see the global event monitor).
//
// Menu interaction is not wired up yet; the four items are inert. The right
// -click NSMenu remains the way to quit, so a broken panel can never strand
// the user with no way out.

/// The battle screen's palette. GBC allowed three colors plus transparency per
/// sprite; we keep that constraint (highlight / base / shadow + black outline).
let GB_BG      = NSColor(white: 0.90, alpha: 1)   // same pill gray as the widget
let GB_INK     = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
let GB_GREEN   = NSColor(srgbRed: 0x40/255, green: 0xB9/255, blue: 0x3E/255, alpha: 1)
let GB_ORANGE  = NSColor(srgbRed: 0xF8/255, green: 0xA8/255, blue: 0x28/255, alpha: 1)
let GB_RED     = NSColor(srgbRed: 0xE8/255, green: 0x30/255, blue: 0x30/255, alpha: 1)
let GB_EXP     = NSColor(srgbRed: 0x40/255, green: 0x90/255, blue: 0xE8/255, alpha: 1)
let GB_YELLOW  = NSColor(srgbRed: 0xF8/255, green: 0xD0/255, blue: 0x28/255, alpha: 1)

func gaugeColor(_ frac: CGFloat) -> NSColor {
    if frac >= 0.5 { return GB_GREEN }
    if frac >= 0.2 { return GB_ORANGE }
    return GB_RED
}

// Claude's battle colors now come from the selected skin (skin(id:).battleColors);
// the "default" skin reproduces the original orange.

/// A ghost monster's palette: a dark core wrapped in purple gas. 'B' is the gas
/// (three tones, shaded), 'C' the near-black core, 'G' its gray highlight, 'W'
/// the eyes, 'R' the red marks, 'M' the tongue.
let bugColors: [Character: NSColor] = [
    ".": .clear,

    // Outline
    "K": NSColor(srgbRed: 0x1F/255, green: 0x24/255, blue: 0x18/255, alpha: 1),

    // Body (다크 올리브)
    "D": NSColor(srgbRed: 0x4B/255, green: 0x5A/255, blue: 0x2E/255, alpha: 1),

    // Highlight (연두 광택)
    "G": NSColor(srgbRed: 0xB8/255, green: 0xD9/255, blue: 0x7A/255, alpha: 1),

    // Face
    "W": .white,

    // Orange (더듬이/집게)
    "O": NSColor(srgbRed: 0xE0/255, green: 0x8A/255, blue: 0x2E/255, alpha: 1),

    // Mouth (붉은 반점)
    "L": NSColor(srgbRed: 0xD9/255, green: 0x5A/255, blue: 0x4A/255, alpha: 1),

    // Wing Aura (이끼 그린)
    "P": NSColor(srgbRed: 0x6F/255, green: 0xA8/255, blue: 0x3E/255, alpha: 1),

    // Wing Aura (shadow)
    "S": NSColor(srgbRed: 0x4E/255, green: 0x7A/255, blue: 0x2A/255, alpha: 1),

    // Mouth (muted edge)
    "M": NSColor(srgbRed: 0xB0/255, green: 0x6E/255, blue: 0x5A/255, alpha: 1),
]

/// Easter egg: the bug repainted as a ladybug (무당벌레). Keyed identically to
/// bugColors, so it is a pure palette swap over the same bugBase grid — no cells
/// are added or moved. Retune these RGBs freely; only the keys must stay in sync
/// with bugColors, or a glyph the grid uses would render as nothing.
///
/// Unlocked by clicking the enemy's black HP plate seven times: the Korean
/// ladybug is 칠성무당벌레 — the seven-spotted one.
let LADYBUG_CLICKS = 7

/// How long the egg's barker holds the dialogue slot before the menu's own
/// message comes back.
let LADYBUG_FLASH_HOLD: TimeInterval = 2.6

let ladybugColors: [Character: NSColor] = [
    ".": .clear,

    // Outline (가장 어두운 빨강)
    "K": NSColor(srgbRed: 0x40/255, green: 0x0C/255, blue: 0x0A/255, alpha: 1),

    // Body (어두운 빨강 — Wing Shell보다 어둡게)
    "D": NSColor(srgbRed: 0x7A/255, green: 0x16/255, blue: 0x13/255, alpha: 1),

    // Highlight (광택)
    "G": NSColor(srgbRed: 0xF4/255, green: 0xA6/255, blue: 0xA0/255, alpha: 1),

    // Face
    "W": .white,

    // Antenna / Spots (검은 반점)
    "O": NSColor(srgbRed: 0x1F/255, green: 0x1F/255, blue: 0x1F/255, alpha: 1),

    // Mouth (검은 반점 포인트)
    "L": NSColor(srgbRed: 0x2A/255, green: 0x2A/255, blue: 0x2A/255, alpha: 1),

    // Wing Shell (중간 빨강)
    "P": NSColor(srgbRed: 0xB8/255, green: 0x24/255, blue: 0x1F/255, alpha: 1),

    // Wing Shell (shadow, Body보다는 밝고 Wing Shell보다는 어둡게)
    "S": NSColor(srgbRed: 0x94/255, green: 0x20/255, blue: 0x1B/255, alpha: 1),

    // Mouth (muted edge)
    "M": NSColor(srgbRed: 0xE6/255, green: 0x7A/255, blue: 0x73/255, alpha: 1),
]

let bugBase: [String] = [
    "...........SS.S.........", // 00
    "...........SS...........", // 01
    ".......SSS.....SS..SS...", // 02
    ".....SSPPPSSS.SPPS.SS...", // 03
    "....SPPPKKKKPPPPPPS.....", // 04
    "....SPKKDDDDKKPPPPS.....", // 05
    "...KSKDDDDDDDDKPPS......", // 06
    "..KWKDDDDDDDDDDKPS.SS...", // 07
    "..KWDDDDDDDDDDDKPPSPPS..", // 08
    "..KWWKDDDDDDDWDDKPPPPS..", // 09
    "SSKWPKDKDDDWWWDDKPPPS..S", // 10
    "SSKWPWDKDWWWWWKDKPPS.SS.", // 11
    "SSPKWDDDWPWWWWKDKPPS.SS.", // 12
    "..SSKDDKWPWWWKDKPPPPS...", // 13
    "....KDDDKWWWDDDKPPPPS...", // 14
    "...SPKMMMDDDMDKPPPPS....", // 15
    "...SPPKKLLM.KKPSPPS.....", // 16
    "....SPPPKKKGKPS.SS......", // 17
    ".....SPPSSPKSS..........", // 18
    "......SS..SS...SS.......", // 19
    "...............SS.......", // 20
]

/// The bug taking a hit: its left eye squeezes shut (the white sliver becomes body
/// with a dark lid line) and its mouth closes to a single dark line. Same grid size
/// and glyphs as bugBase, so it is a drop-in swap while the hit flash plays.
let bugHurtBase: [String] = [
    "...........SS.S.........", // 00
    "...........SS...........", // 01
    ".......SSS.....SS..SS...", // 02
    ".....SSPPPSSS.SPPS.SS...", // 03
    "....SPPPKKKKPPPPPPS.....", // 04
    "....SPKKDDDDKKPPPPS.....", // 05
    "...KSKDDDDDDDDKPPS......", // 06
    "..KKDDDDDDDDDDDKPS.SS...", // 07
    "..KDDDDDDDDDDDDKPPSPPS..", // 08
    "..KKDKDDDDDDDDDDKPPPPS..", // 09
    "SSKWKKDKDDDDWWDDKPPPS..S", // 10
    "SSKWPDDKDDWWWWKDKPPS.SS.", // 11
    "SSPKWKDDDPWWWWKDKPPS.SS.", // 12
    "..SSKDDKWPWWWKDKPPPPS...", // 13
    "....KDDDKWWWDDDKPPPPS...", // 14
    "...SPKKKKKKKDDKPPPPS....", // 15
    "...SPPKKDDDDKKPSPPS.....", // 16
    "....SPPPKKKKKPS.SS......", // 17
    ".....SPPSSPKSS..........", // 18
    "......SS..SS...SS.......", // 19
    "...............SS.......", // 20
]

/// Light comes from the top-left. Each body ('B') cell's tone follows a diagonal
/// gradient (horizontal position within its row + vertical position overall),
/// and only the cells where two tones meet get checkerboard-dithered.
///
/// Dithering whole columns instead produces vertical stripes that read as grime,
/// not as retro shading — the boundary is the only place it belongs.
func battleShaded(_ grid: [String], flatten: Bool = false) -> [String] {
    let rows = grid.count
    return grid.enumerated().map { (r, line) -> String in
        var chars = Array(line)
        let body = chars.indices.filter { chars[$0] == "B" }
        guard let first = body.first, let last = body.last, last > first else { return line }
        for i in body {
            let u = Double(i - first) / Double(last - first)
            let v = Double(r) / Double(max(rows - 1, 1))
            // A flat body (the bug's shell) leans on horizontal position alone.
            let t = flatten ? (0.75 * u + 0.25 * v) : (0.55 * u + 0.45 * v)
            let dither = (r + i) % 2 == 0
            switch t {
            case ..<0.26: chars[i] = "L"
            case ..<0.34: chars[i] = dither ? "L" : "B"
            case ..<0.62: chars[i] = "B"
            case ..<0.70: chars[i] = dither ? "D" : "B"
            default:      chars[i] = "D"
            }
        }
        return String(chars)
    }
}

/// Claude from behind, hand-shaded. 24x21 — the bug's density, so the two sprites
/// read as the same era instead of the widget's 20x14 grid blown up beside it.
///
/// This no longer derives from clawdBase. The widget grid is drawn for a 22px
/// menu bar and only ever loses its face here, which left the back as a flat
/// blob next to the bug. Shape (silhouette, ears, the neck crease, where the
/// limbs clear the body) is now authored here and is deliberately NOT synced to
/// the widget. Color still is: the glyphs are exactly the four ClawdSkin.battleColors
/// keys, so every skin recolors this for free.
///   K = outline · L = lit (upper-left) · B = base · D = shadow (lower-right)
/// Adding a fifth glyph would render as nothing — battleColors has no key for it.
///
/// Light comes from the upper-left, so L hugs the top-left curve of the head and
/// back, D pools along the lower-right and under the head where it overhangs the
/// body. Gen-2 backs are lit this way and carry no spine seam.
///
/// The arms are held out to the sides, as in the Clawd mascot — short, stubby,
/// and clear of the body so the silhouette reads as a pose rather than a slab.
/// They are the widest part of the sprite, so the body is narrowed to make room
/// for them inside the same 24 columns.
///
/// Rows 18-20 (the lower body) are drawn but never seen: the dialog box crops
/// them, exactly as a Gen-2 back sprite is cropped at the waist. That is intended
/// — do not raise the sprite to reveal them.
let clawdBackBase: [String] = [
    "........KKKKKKKKK.........", // 00  ear tips
    "......KKLLLLBBBDDKK.......", // 01  near ear is lit, far ear sits in shade
    ".....KKLLLBBBBBBDDDKK.....", // 02  ears meet the head
    "....KKLLLBBBBBBBBBDDDK....", // 03  back of the head: L mass upper-left,
    "....KLLLBBBBBBBBBBBDDDK...", // 04  D mass lower-right, B between them
    "....KLLBBBBBBBBBBBBBDDK...", // 05
    "....KLLBBBBBBBBBBBBBDDK...", // 06
    "....KLLBBBBBBBBBBBBBDDK...", // 07  neck crease: shadow pools under the head
    "....KLLBBBBBBBBBBBBBDDK...", // 08  shoulders
    ".KKKKLLBBBBBBBBBBBBDDKKKK.", // 09  Arms spread wide. The near arm is lit and is
    "KLLLKLLBBBBBBBBBBBBDDDDDDK", // 10  cut from the torso by a K seam; the far arm has
    "KLLBKLLBBBBBBBBBBBBDDDDDDK", // 11  no seam and is filled entirely with D.
    "KKBBKLLLBBBBBBBBBBBDDDDDDK", // 12  Light comes from the upper-left, so the far arm
    ".KKKKLLLBBBBBBBBBBBDDKKKK.", // 13  can never be brighter than the shadow it sits in.
    "....KLLLBBBBBBBBBBBBDDDK..", // 14
    "....KLLLBBBBBBBBBBBBDDDK..", // 15
    "....KLLLBBBBBBBBBBBBDDDK..", // 16
    ".....KLLBKKBBKKBBKKBDDK...", // 17  underside: three gaps cut four legs, as in
    ".....KLLBKKLBKKBDKKBDDK...", // 18  the widget grid (clawdBase rows 12-13) —
    "......KKKKKKKKKKKKKKKK....", // 19  Clawd has four, not two. Below the crop line.
]

func clawdBackGrid() -> [String] { clawdBackBase }

func spriteSize(_ grid: [String], cell: CGFloat) -> NSSize {
    NSSize(width: CGFloat(grid[0].count) * cell, height: CGFloat(grid.count) * cell)
}

let BATTLE_W: CGFloat = 480
let BATTLE_H: CGFloat = 300

let BATTLE_ENEMY_NAME  = "버그"

/// Which page of the 2x2 menu is showing. Choosing 사용량/기능 swaps only the
/// dialogue box; the battle scene above it stays put.
