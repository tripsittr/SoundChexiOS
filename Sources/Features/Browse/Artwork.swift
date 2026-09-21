// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// An item's cover, with a type-appropriate glyph while it loads or when there
/// is none. Artwork URLs are public, so this loads them directly.
///
/// The shape follows the kind of thing shown, matching the Spotify references
/// (S-288): albums, songs and playlists are rounded squares; an artist is a
/// circle. Callers pass `.circle` for artist art; the default stays the rounded
/// square everything else uses.
struct Artwork: View {
    enum Shape {
        case roundedSquare(CGFloat)
        case circle

        static let square = Shape.roundedSquare(6)
    }

    let item: MediaItem
    var size: CGFloat = 44
    var aspect: CGFloat = 1
    var shape: Shape = .square

    var body: some View {
        Group {
            if let url = item.artwork {
                // Disk-cached, so a cover already seen loads instantly and works
                // offline — AsyncImage kept nothing and re-fetched every scroll.
                CachedImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size * aspect)
        .clipped()
        .clipShape(clipShape)
    }

    private var clipShape: AnyShape {
        switch shape {
        case .roundedSquare(let radius): AnyShape(RoundedRectangle(cornerRadius: radius))
        case .circle: AnyShape(Circle())
        }
    }

    private var placeholder: some View {
        SoundChexTheme.base700
            .overlay(
                Image(systemName: glyph)
                    .foregroundStyle(SoundChexTheme.ink500)
                    .font(.system(size: size * 0.4))
            )
    }

    private var glyph: String {
        switch item.type {
        case .music: "music.note"
        case .movie: "film"
        case .show: "tv"
        case .book: "book"
        case .unknown: "square"
        }
    }
}
