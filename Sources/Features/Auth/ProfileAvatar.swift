// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A profile's avatar: its image when it has one, otherwise a coloured tile with
/// its initial — the same treatment the web app uses. Rounded-square, sized by
/// the caller, so it works both large on the picker and small in a switcher.
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 96

    var body: some View {
        Group {
            if let url = profile.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialTile
                }
            } else {
                initialTile
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.16))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.16)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var initialTile: some View {
        tileColor
            .overlay(
                Text(profile.initial ?? String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    /// The profile's colour, or the accent as a fallback.
    private var tileColor: Color {
        if let hex = profile.color, let color = Color(hex: hex) {
            return color
        }
        return SoundChexTheme.accent
    }
}

extension Color {
    /// Parses a "#rrggbb" (or "rrggbb") hex string. Nil when it isn't one.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
