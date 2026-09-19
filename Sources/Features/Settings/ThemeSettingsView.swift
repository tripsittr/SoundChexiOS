// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Lets the user make the app theirs: appearance (system/light/dark), an accent
/// colour, and the background tone — with a live preview and presets, plus a
/// free colour picker for full control. Everything writes to `ThemeStore`, which
/// the whole app reads, so changes apply the instant they are made.
struct ThemeSettingsView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.colorScheme) private var scheme

    /// A small set of on-brand accents, plus "Custom" via the picker.
    private let accentPresets: [(name: String, hex: UInt32)] = [
        ("SoundChex", 0xE11D3A),
        ("Ember", 0xFF6B35),
        ("Amber", 0xF5A623),
        ("Lime", 0x84CC16),
        ("Emerald", 0x10B981),
        ("Teal", 0x14B8A6),
        ("Sky", 0x38BDF8),
        ("Indigo", 0x6366F1),
        ("Violet", 0x8B5CF6),
        ("Magenta", 0xEC4899),
    ]

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(ThemeStore.Appearance.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Accent") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 5), spacing: 14) {
                    ForEach(accentPresets, id: \.hex) { preset in
                        swatch(hex: preset.hex, isSelected: theme.accentHex == preset.hex) {
                            theme.accentHex = preset.hex
                        }
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("Custom accent", selection: accentBinding, supportsOpacity: false)
            }

            Section {
                ColorPicker("Dark background", selection: darkBgBinding, supportsOpacity: false)
                ColorPicker("Light background", selection: lightBgBinding, supportsOpacity: false)
            } header: {
                Text("Background")
            } footer: {
                Text("Full control is yours. Accents are nudged automatically if they'd be hard to read on your background.")
            }

            if theme.hasCustomised {
                Section {
                    Button(role: .destructive) { theme.reset() } label: {
                        Label("Reset to SoundChex defaults", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Live preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surface(for: scheme))
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "music.note").foregroundStyle(theme.legibleAccent(on: scheme)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing").font(.headline)
                    Text("Your accent, live").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.legibleAccent(on: scheme))
            }
            Capsule()
                .fill(theme.accent)
                .frame(height: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: 180, alignment: .leading)
                .background(Capsule().fill(theme.surface(for: scheme)))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.background(for: scheme)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.surface(for: scheme), lineWidth: 1))
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func swatch(hex: UInt32, isSelected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Circle()
                .fill(Color(hex: hex))
                .frame(height: 40)
                .overlay(
                    Circle().stroke(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        .padding(2)
                )
                .overlay(
                    isSelected ? Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) : nil
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings between the store's hex ints and SwiftUI Color

    private var appearanceBinding: Binding<ThemeStore.Appearance> {
        Binding(get: { theme.appearance }, set: { theme.appearance = $0 })
    }

    private var accentBinding: Binding<Color> {
        Binding(get: { theme.accent }, set: { theme.accentHex = $0.hexValue })
    }

    private var darkBgBinding: Binding<Color> {
        Binding(get: { Color(hex: theme.backgroundDarkHex) }, set: { theme.backgroundDarkHex = $0.hexValue })
    }

    private var lightBgBinding: Binding<Color> {
        Binding(get: { Color(hex: theme.backgroundLightHex) }, set: { theme.backgroundLightHex = $0.hexValue })
    }
}

extension Color {
    /// The colour as a 0xRRGGBB integer (opacity dropped).
    var hexValue: UInt32 {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(max(0, min(255, r * 255)))
        let gi = UInt32(max(0, min(255, g * 255)))
        let bi = UInt32(max(0, min(255, b * 255)))
        return (ri << 16) | (gi << 8) | bi
    }
}
