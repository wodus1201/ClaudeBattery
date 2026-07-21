import Cocoa

// MARK: - Shiny sparkle

/// The four-pointed star of the Pokémon shiny effect, as a pixel grid so it sits
/// on the same grid as the sprites instead of looking like a vector overlay.
/// 'E' is a darker gold rim: on the panel's light gray a pure-gold star washes
/// out, so the points are edged to hold their shape.
let SPARKLE_GRID: [String] = [
    "...E...",
    "...S...",
    "..ESE..",
    ".ESWSE.",
    "ESSWSSE",
    ".ESWSE.",
    "..ESE..",
    "...S...",
    "...E...",
]

/// The menu-bar star. A 22px bar leaves the sprite ~18pt tall, and scaling the
/// 9-row grid into that gives sub-point cells — which vanish outright, since
/// drawSprite() fills with antialiasing off. So small frames get their own
/// coarse grid instead of a shrunken fine one.
let SPARKLE_GRID_SMALL: [String] = [
    ".S.",
    "SWS",
    ".S.",
]

/// Below this frame height the fine grid can't hold a whole point per cell.
let SPARKLE_SMALL_BELOW: CGFloat = 40

/// Where the stars pop, as offsets from the sprite's center in *sprite cells*, so
/// one layout works at any cell size. Each carries its own scale and the fraction
/// of the burst it appears at, so they fire in sequence rather than all at once —
/// a simultaneous pop reads as a flash, a staggered one reads as a sparkle.
let SPARKLE_BURST: [(dx: CGFloat, dy: CGFloat, scale: CGFloat, at: Double)] = [
    (-0.42,  0.34, 1.00, 0.00),
    ( 0.40,  0.18, 0.75, 0.14),
    (-0.22, -0.30, 0.70, 0.30),
    ( 0.30, -0.36, 0.55, 0.46),
]

/// How long the entrance burst lasts.
let SPARKLE_DURATION: TimeInterval = 1.1

/// Draw the burst over `frame` at `t` in 0...1. Each star fades in fast and out
/// slow within its own window, so the group twinkles instead of blinking as one.
///
/// Star size is a fraction of `frame`, never an absolute: the same call has to
/// work over a 122pt battle sprite and an 18pt one in a 22px menu bar, and a
/// fixed cell size that suits either one is grotesque in the other.
func drawSparkles(in frame: NSRect, t: Double, gold: NSColor) {
    guard t >= 0, t <= 1 else { return }
    let colors: [Character: NSColor] = ["S": gold, "W": .white, "E": SHINY_GOLD_EDGE]
    let small = frame.height < SPARKLE_SMALL_BELOW
    let grid = small ? SPARKLE_GRID_SMALL : SPARKLE_GRID
    let rows = CGFloat(grid.count)
    // The biggest star spans ~40% of the sprite's height.
    let unit = frame.height * 0.40 / rows
    for s in SPARKLE_BURST {
        let local = (t - s.at) / 0.5          // each star owns half the burst
        guard local >= 0, local <= 1 else { continue }
        // Fade: quick rise, slow fall. sin gives that shape over 0...1 for free.
        let alpha = sin(local * .pi)
        guard alpha > 0.02 else { continue }

        // Never let a cell fall below a point: drawSprite() fills with antialiasing
        // off, so a sub-point rect rounds away to nothing and the star disappears.
        let cell = max(unit * s.scale, 1)
        let w = CGFloat(grid[0].count) * cell
        let h = CGFloat(grid.count) * cell
        let origin = NSPoint(x: frame.midX + s.dx * frame.width - w / 2,
                             y: frame.midY + s.dy * frame.height - h / 2)

        NSGraphicsContext.current?.saveGraphicsState()
        // The whole star fades as one; per-cell alpha would dither at these sizes.
        let faded = colors.mapValues { $0.withAlphaComponent(CGFloat(alpha)) }
        drawSprite(grid, origin: origin, cell: cell, colors: faded)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

/// The shiny's star color, and the ★ used to mark it in menus.
let SHINY_GOLD = NSColor(srgbRed: 0xFF/255, green: 0xDE/255, blue: 0x6A/255, alpha: 1)
let SHINY_GOLD_EDGE = NSColor(srgbRed: 0xC8/255, green: 0x8A/255, blue: 0x18/255, alpha: 1)
let SHINY_MARK = "★"

/// The menu-bar twinkle, in animation ticks (the widget timer runs at 12fps).
/// The widget redraws only when its signature changes, so the sparkle is stepped
/// as an integer frame index: it burns ~24 frames every 30s and is idle between.
let WIDGET_SPARKLE_PERIOD = 360      // 30s at 12fps
let WIDGET_SPARKLE_FRAMES = 24       // 2s of twinkle
