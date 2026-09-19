// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The live, user-customisable theme.
///
/// `SoundChexTheme` is the static default palette (matched to the web app). This
/// store lets a user override the parts that are theirs to choose — the accent,
/// the background tone, and light/dark/system appearance — and have every screen
/// update at once, because views read their colours from the store in the
/// environment rather than from the static enum.
///
/// Persisted per device with `@AppStorage`. Colours are stored as 0xRRGGBB
/// integers. Full colour control is allowed, with a contrast guardrail so a
/// chosen accent stays legible on the chosen background.
@Observable
final class ThemeStore {
    /// Appearance the user asked for.
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    // MARK: - Stored preferences (backed by UserDefaults)

    private enum Keys {
        static let appearance = "theme.appearance"
        static let accent = "theme.accent"
        static let backgroundDark = "theme.background.dark"
        static let backgroundLight = "theme.background.light"
        static let custom = "theme.custom" // whether the user has overridden anything
    }

    /// The SoundChex defaults, used until the user changes something.
    static let defaultAccent: UInt32 = 0xE11D3A
    static let defaultBackgroundDark: UInt32 = 0x08080B
    static let defaultBackgroundLight: UInt32 = 0xF7F7F8

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// The accent, as 0xRRGGBB. Every accent read in the app resolves here.
    var accentHex: UInt32 {
        didSet { defaults.set(Int(accentHex), forKey: Keys.accent); markCustom(); syncPalette() }
    }

    /// The app background for dark mode.
    var backgroundDarkHex: UInt32 {
        didSet { defaults.set(Int(backgroundDarkHex), forKey: Keys.backgroundDark); markCustom(); syncPalette() }
    }

    /// The app background for light mode.
    var backgroundLightHex: UInt32 {
        didSet { defaults.set(Int(backgroundLightHex), forKey: Keys.backgroundLight); markCustom(); syncPalette() }
    }

    private(set) var hasCustomised: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .dark
        self.accentHex = Self.readHex(defaults, Keys.accent) ?? Self.defaultAccent
        self.backgroundDarkHex = Self.readHex(defaults, Keys.backgroundDark) ?? Self.defaultBackgroundDark
        self.backgroundLightHex = Self.readHex(defaults, Keys.backgroundLight) ?? Self.defaultBackgroundLight
        self.hasCustomised = defaults.bool(forKey: Keys.custom)
        syncPalette()
    }

    /// Push the current colours into the shared palette so the static
    /// `SoundChexTheme.*` accessors (used across the app without the environment)
    /// resolve to the user's choices and the right scheme.
    private func syncPalette() {
        ThemePalette.shared.apply(
            accent: accentHex,
            backgroundDark: backgroundDarkHex,
            backgroundLight: backgroundLightHex
        )
    }

    private static func readHex(_ d: UserDefaults, _ key: String) -> UInt32? {
        d.object(forKey: key) == nil ? nil : UInt32(truncatingIfNeeded: d.integer(forKey: key))
    }

    private func markCustom() {
        if !hasCustomised {
            hasCustomised = true
            defaults.set(true, forKey: Keys.custom)
        }
    }

    /// Restore the SoundChex defaults.
    func reset() {
        appearance = .dark
        accentHex = Self.defaultAccent
        backgroundDarkHex = Self.defaultBackgroundDark
        backgroundLightHex = Self.defaultBackgroundLight
        hasCustomised = false
        defaults.set(false, forKey: Keys.custom)
    }

    // MARK: - Resolved colours

    var accent: Color { Color(hex: accentHex) }

    /// A brighter accent for pressed/hover, derived from the accent.
    var accentHot: Color { Color(hex: accentHex).lighter(by: 0.12) }

    /// The base background for the *effective* scheme. `scheme` is what the
    /// environment resolved (system may be either), so pass it in from the view.
    func background(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .light ? backgroundLightHex : backgroundDarkHex)
    }

    /// Card / raised-surface fill, a step off the background toward mid.
    func surface(for scheme: ColorScheme) -> Color {
        let base = scheme == .light ? backgroundLightHex : backgroundDarkHex
        return scheme == .light ? Color(hex: base).darker(by: 0.04) : Color(hex: base).lighter(by: 0.05)
    }

    /// An accent guaranteed legible as text/on a fill over the given scheme's
    /// background — the guardrail on full colour control. If the raw accent is
    /// too low-contrast against the background, it is lightened or darkened until
    /// it clears a minimum contrast ratio.
    func legibleAccent(on scheme: ColorScheme) -> Color {
        let bg = scheme == .light ? backgroundLightHex : backgroundDarkHex
        return Color(hex: adjustForContrast(accentHex, against: bg, minRatio: 3.0))
    }

    // MARK: - Contrast maths (WCAG relative luminance)

    private func adjustForContrast(_ fg: UInt32, against bg: UInt32, minRatio: Double) -> UInt32 {
        var color = fg
        let bgLum = Self.luminance(bg)
        // Lighten on a dark background, darken on a light one, until it clears.
        let lightenTarget = bgLum < 0.5
        var steps = 0
        while Self.contrastRatio(color, bg) < minRatio && steps < 20 {
            color = lightenTarget ? Self.scale(color, 1.08) : Self.scale(color, 0.92)
            steps += 1
        }
        return color
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func chan(_ v: Double) -> Double {
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = chan(Double((hex >> 16) & 0xFF))
        let g = chan(Double((hex >> 8) & 0xFF))
        let b = chan(Double(hex & 0xFF))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        let (hi, lo) = (max(la, lb), min(la, lb))
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func scale(_ hex: UInt32, _ factor: Double) -> UInt32 {
        func c(_ v: UInt32) -> UInt32 { UInt32(min(255, max(0, Double(v) * factor))) }
        let r = c((hex >> 16) & 0xFF)
        let g = c((hex >> 8) & 0xFF)
        let b = c(hex & 0xFF)
        return (r << 16) | (g << 8) | b
    }
}

// MARK: - Small colour helpers

extension Color {
    /// Lighten toward white by `amount` (0…1).
    func lighter(by amount: Double) -> Color {
        blended(with: .white, amount: amount)
    }

    /// Darken toward black by `amount` (0…1).
    func darker(by amount: Double) -> Color {
        blended(with: .black, amount: amount)
    }

    private func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(min(1, max(0, amount)))
        return Color(
            red: Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue: Double(ab + (bb - ab) * t)
        )
    }
}
