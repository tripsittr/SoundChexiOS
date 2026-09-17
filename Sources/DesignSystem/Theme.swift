import SwiftUI

/// The app's palette and shapes, matching the web media center exactly so the
/// two feel like one product. Values are the tokens in resources/css/tokens.css
/// (and the interpolated ink shades the Blade markup uses but the tokens omit).
enum SoundChexTheme {
    // Base — near-black, slightly blue.
    static let base900 = Color(hex: 0x08080B) // app background
    static let base800 = Color(hex: 0x0F0F14) // cards, nav fill, popovers
    static let base700 = Color(hex: 0x16161D) // artwork placeholders, hover fills
    static let base600 = Color(hex: 0x1F1F28) // borders, dividers, seek track
    static let base500 = Color(hex: 0x2A2A35) // subtle borders

    // Ink — text.
    static let ink100 = Color(hex: 0xF4F4F5) // primary
    static let ink200 = Color(hex: 0xD6D6DC) // interpolated
    static let ink300 = Color(hex: 0xB8B8C0) // secondary
    static let ink400 = Color(hex: 0xA1A1AC) // interpolated
    static let ink500 = Color(hex: 0x8A8A96) // muted, inactive tabs
    static let ink600 = Color(hex: 0x6B6B78) // interpolated (separators)

    // Accent — the SoundChex red.
    static let accent = Color(hex: 0xE11D3A)
    static let accentHot = Color(hex: 0xFF2A4A) // hover/pressed

    // Status.
    static let storedGreen = Color(hex: 0x34D399)
    static let errorPink = Color(hex: 0xFCA5A5)
    static let amber = Color(hex: 0xFBBF24)

    /// The web app's transition curve (cubic-bezier(0.16, 1, 0.3, 1)).
    static let easeOut = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)

    // Corner radii, in points, matching the CSS.
    static let radiusPoster: CGFloat = 8
    static let radiusLargeArt: CGFloat = 12
    static let radiusButton: CGFloat = 6
}

extension Color {
    /// From a 0xRRGGBB integer.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
