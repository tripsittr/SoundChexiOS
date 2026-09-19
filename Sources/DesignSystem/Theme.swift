// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The app's palette and shapes, matching the web media center exactly so the
/// two feel like one product. Values are the tokens in resources/css/tokens.css
/// (and the interpolated ink shades the Blade markup uses but the tokens omit).
///
/// The colours are **dynamic**, not frozen:
///
/// - `base*` and `ink*` resolve per the view's colour scheme (light vs dark), so
///   the whole app — including the 200-odd call sites that reference these
///   statically — flips when the user picks Light. On dark they are the web
///   palette; on light they are the mirrored ramp, derived from the user's
///   chosen light background the same way the web `theme.js` derives it.
/// - `accent`/`accentHot` follow the user's chosen accent, read live from the
///   same store the Appearance settings write to.
///
/// The live values come from `ThemePalette`, which `ThemeStore` keeps in sync.
/// This is what lets a static `SoundChexTheme.accent` stay correct without every
/// call site reaching into the environment.
enum SoundChexTheme {
    // Base — the app's ground and raised surfaces. Dark by default (the web
    // near-black), light when the effective scheme is light.
    static var base900: Color { ThemePalette.shared.dynamic(\.base900) } // app background
    static var base800: Color { ThemePalette.shared.dynamic(\.base800) } // cards, nav fill, popovers
    static var base700: Color { ThemePalette.shared.dynamic(\.base700) } // artwork placeholders, hover fills
    static var base600: Color { ThemePalette.shared.dynamic(\.base600) } // borders, dividers, seek track
    static var base500: Color { ThemePalette.shared.dynamic(\.base500) } // subtle borders

    // Ink — text. Light-on-dark by default, dark-on-light in light mode.
    static var ink100: Color { ThemePalette.shared.dynamic(\.ink100) } // primary
    static var ink200: Color { ThemePalette.shared.dynamic(\.ink200) } // interpolated
    static var ink300: Color { ThemePalette.shared.dynamic(\.ink300) } // secondary
    static var ink400: Color { ThemePalette.shared.dynamic(\.ink400) } // interpolated
    static var ink500: Color { ThemePalette.shared.dynamic(\.ink500) } // muted, inactive tabs
    static var ink600: Color { ThemePalette.shared.dynamic(\.ink600) } // interpolated (separators)

    // Accent — the user's chosen accent (SoundChex red by default).
    static var accent: Color { Color(hex: ThemePalette.shared.accentHex) }
    static var accentHot: Color { Color(hex: ThemePalette.shared.accentHex).lighter(by: 0.12) }

    // Status — the same in both schemes (they read as a status, not a surface).
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

/// The live source of the app's scheme-dependent colours.
///
/// A tiny, UIKit-backed holder so `SoundChexTheme`'s static accessors can return
/// **dynamic** `UIColor`s (ones that resolve differently for light and dark trait
/// collections) without threading the SwiftUI environment through every view.
/// `ThemeStore` calls `apply(...)` whenever the user changes their accent or
/// background, which rebuilds the ramps.
///
/// The ramps mirror the web app: on dark, the fixed near-black web palette
/// stepped up toward mid; on light, the same steps taken *down* from the chosen
/// light background, with the ink ramp flipped to stay legible.
/// Thread-safety: the mutable ramps are read while building colours (on the main
/// thread, from SwiftUI view bodies and the static `SoundChexTheme` accessors)
/// and written only by `ThemeStore` (a `@MainActor` type). All access is
/// therefore main-thread; the `nonisolated(unsafe)` markers state that contract
/// to the compiler without forcing main-actor isolation onto the 200-odd
/// call sites that read `SoundChexTheme.*` synchronously.
final class ThemePalette: @unchecked Sendable {
    static let shared = ThemePalette()

    /// One scheme's fully-resolved ramp, as 0xRRGGBB integers.
    struct Ramp: Sendable {
        var base900, base800, base700, base600, base500: UInt32
        var ink100, ink200, ink300, ink400, ink500, ink600: UInt32
    }

    nonisolated(unsafe) private(set) var accentHex: UInt32 = ThemeStore.defaultAccent
    nonisolated(unsafe) private(set) var dark = ThemePalette.defaultDark
    nonisolated(unsafe) private(set) var light = ThemePalette.buildLight(from: ThemeStore.defaultBackgroundLight)

    /// Recompute the ramps from the user's chosen accent and backgrounds.
    func apply(accent: UInt32, backgroundDark: UInt32, backgroundLight: UInt32) {
        accentHex = accent
        dark = ThemePalette.buildDark(from: backgroundDark)
        light = ThemePalette.buildLight(from: backgroundLight)
    }

    /// A SwiftUI colour that resolves to the light or dark ramp value depending
    /// on the trait collection it is rendered in.
    ///
    /// The two ramps are snapshotted into the (Sendable) closure as plain values
    /// so the dynamic provider — which UIKit may invoke off the main actor when a
    /// trait changes — captures no main-actor state.
    func dynamic(_ key: KeyPath<Ramp, UInt32>) -> Color {
        let lightValue = light[keyPath: key]
        let darkValue = dark[keyPath: key]
        return Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .light ? lightValue : darkValue)
        })
    }

    // MARK: - Ramp construction

    /// The web app's dark palette, exact — the tokens in tokens.css. When the
    /// user has not changed the dark background it is these; when they have, the
    /// surfaces step off their chosen background instead.
    static let defaultDark = Ramp(
        base900: 0x08080B, base800: 0x0F0F14, base700: 0x16161D, base600: 0x1F1F28, base500: 0x2A2A35,
        ink100: 0xF4F4F5, ink200: 0xD6D6DC, ink300: 0xB8B8C0, ink400: 0xA1A1AC, ink500: 0x8A8A96, ink600: 0x6B6B78
    )

    private static func buildDark(from bg: UInt32) -> Ramp {
        // Default background keeps the exact web ramp; a custom one derives from it.
        guard bg != ThemeStore.defaultBackgroundDark else { return defaultDark }
        return Ramp(
            base900: bg,
            base800: lighten(bg, 0.04),
            base700: lighten(bg, 0.08),
            base600: lighten(bg, 0.13),
            base500: lighten(bg, 0.20),
            // Ink stays light on a dark ground regardless of the exact background.
            ink100: 0xF4F4F5, ink200: 0xD6D6DC, ink300: 0xB8B8C0,
            ink400: 0xA1A1AC, ink500: 0x8A8A96, ink600: 0x6B6B78
        )
    }

    private static func buildLight(from bg: UInt32) -> Ramp {
        // Surfaces step *darker* than the light background; ink is dark-on-light.
        Ramp(
            base900: bg,
            base800: darken(bg, 0.03),
            base700: darken(bg, 0.06),
            base600: darken(bg, 0.10),
            base500: darken(bg, 0.16),
            ink100: 0x111114, // primary text
            ink200: 0x27272C,
            ink300: 0x3D3D44, // secondary
            ink400: 0x55555F,
            ink500: 0x6B6B78, // muted
            ink600: 0x8A8A96  // separators
        )
    }

    // Small integer colour maths (mirrors theme.js).
    private static func lighten(_ hex: UInt32, _ amount: Double) -> UInt32 {
        chan(hex) { v in v + (255 - v) * amount }
    }
    private static func darken(_ hex: UInt32, _ amount: Double) -> UInt32 {
        chan(hex) { v in v * (1 - amount) }
    }
    private static func chan(_ hex: UInt32, _ f: (Double) -> Double) -> UInt32 {
        let r = UInt32(min(255, max(0, f(Double((hex >> 16) & 0xFF)))))
        let g = UInt32(min(255, max(0, f(Double((hex >> 8) & 0xFF)))))
        let b = UInt32(min(255, max(0, f(Double(hex & 0xFF)))))
        return (r << 16) | (g << 8) | b
    }
}

extension UIColor {
    /// From a 0xRRGGBB integer.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
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
