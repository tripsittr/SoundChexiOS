// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A poster tile matching the web `.poster`: cover art with a bottom scrim and
/// the title/subtitle over it. Used in the home rails and browse grids.
struct PosterTile: View {
    let item: MediaItem
    /// Rail width; the height follows from the type's aspect ratio.
    var width: CGFloat = 144

    private var aspect: CGFloat { item.type == .music ? 1 : 1.5 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(item: item, size: width, aspect: aspect)

            // The scrim: base-900 fading up so the title reads over any art.
            LinearGradient(
                stops: [
                    .init(color: SoundChexTheme.base900.opacity(0.95), location: 0),
                    .init(color: SoundChexTheme.base900.opacity(0.6), location: 0.35),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .bottom, endPoint: .top
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .lineLimit(2)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(SoundChexTheme.ink300)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .padding(.top, 22)
        }
        .frame(width: width, height: width * aspect)
        .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
    }

    /// "subtitle • year", the way the web poster joins them.
    private var subtitle: String? {
        let parts = [item.subtitle, item.meta?.releaseYear.map(String.init)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
