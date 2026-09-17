import SwiftUI

/// The app's palette, matching the web media center so the two feel like one
/// product. The values mirror resources/css/tokens.css on the server.
enum SoundChexTheme {
    /// The SoundChex red, used for the primary action and the now-playing accent.
    static let accent = Color(red: 0xE1 / 255, green: 0x1D / 255, blue: 0x3A / 255)

    static let base900 = Color(red: 0x08 / 255, green: 0x08 / 255, blue: 0x0B / 255)
    static let base800 = Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x18 / 255)
    static let base700 = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x22 / 255)

    static let ink100 = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255)
    static let ink300 = Color(red: 0xD4 / 255, green: 0xD4 / 255, blue: 0xD8 / 255)
    static let ink500 = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255)
}
