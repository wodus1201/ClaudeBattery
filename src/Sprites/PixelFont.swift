import Cocoa
import CoreText

// MARK: - Pixel font

/// Register the bundled NeoDunggeunmo pixel font so we can use it by name.
func registerPixelFont() {
    guard let url = Bundle.main.url(forResource: "neodgm", withExtension: "ttf") else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

/// Pixel font at a given size, falling back to a monospaced system font.
func pixelFont(_ size: CGFloat) -> NSFont {
    NSFont(name: PIXEL_FONT_NAME, size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
}
