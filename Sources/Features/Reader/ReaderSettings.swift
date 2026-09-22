// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The reader's look — font size, face, and page theme (S-295).
///
/// Per-device reading comfort, remembered across books in UserDefaults. Not
/// synced (it is a per-device preference, like brightness), so a plain struct
/// with a load/save is enough.
struct ReaderSettings: Equatable {
    var fontSize: Double = 19
    var serif: Bool = true
    var theme: Theme = .sepia

    enum Theme: String, CaseIterable, Identifiable {
        case light, sepia, dark
        var id: String { rawValue }

        var background: Color {
            switch self {
            case .light: Color(white: 0.98)
            case .sepia: Color(red: 0.96, green: 0.93, blue: 0.86)
            case .dark: SoundChexTheme.base900
            }
        }

        var text: Color {
            switch self {
            case .light: Color(white: 0.1)
            case .sepia: Color(red: 0.24, green: 0.19, blue: 0.12)
            case .dark: SoundChexTheme.ink200
            }
        }

        /// A control tint that reads on this page.
        var tint: Color {
            self == .dark ? SoundChexTheme.accent : SoundChexTheme.ink500
        }

        var label: String {
            switch self {
            case .light: "Light"
            case .sepia: "Sepia"
            case .dark: "Dark"
            }
        }
    }

    // MARK: - Persistence

    private static let key = "soundchex.reader.settings"

    func save() {
        let dict: [String: Any] = [
            "fontSize": fontSize,
            "serif": serif,
            "theme": theme.rawValue,
        ]
        UserDefaults.standard.set(dict, forKey: Self.key)
    }

    static func load() -> ReaderSettings {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) else { return ReaderSettings() }
        var settings = ReaderSettings()
        if let size = dict["fontSize"] as? Double { settings.fontSize = size }
        if let serif = dict["serif"] as? Bool { settings.serif = serif }
        if let theme = dict["theme"] as? String, let parsed = Theme(rawValue: theme) { settings.theme = parsed }
        return settings
    }
}

/// The reader's appearance controls, raised as a small sheet.
struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 20) {
            // Font size.
            HStack(spacing: 20) {
                Button { adjust(-1) } label: { Image(systemName: "textformat.size.smaller") }
                Slider(value: $settings.fontSize, in: 13 ... 30, step: 1)
                Button { adjust(1) } label: { Image(systemName: "textformat.size.larger") }
            }
            .font(.title3)

            // Face.
            Picker("Face", selection: $settings.serif) {
                Text("Serif").tag(true)
                Text("Sans").tag(false)
            }
            .pickerStyle(.segmented)

            // Theme.
            HStack(spacing: 12) {
                ForEach(ReaderSettings.Theme.allCases) { theme in
                    Button {
                        settings.theme = theme
                        settings.save()
                    } label: {
                        Text("A")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                            .frame(width: 56, height: 44)
                            .background(theme.background, in: .rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(settings.theme == theme ? SoundChexTheme.accent : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .onChange(of: settings.fontSize) { settings.save() }
        .onChange(of: settings.serif) { settings.save() }
    }

    private func adjust(_ delta: Double) {
        settings.fontSize = min(30, max(13, settings.fontSize + delta))
        settings.save()
    }
}
