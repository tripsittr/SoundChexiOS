import SwiftUI

/// An item's cover, with a type-appropriate glyph while it loads or when there
/// is none. Artwork URLs are public, so this loads them directly.
struct Artwork: View {
    let item: MediaItem
    var size: CGFloat = 44
    var aspect: CGFloat = 1

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
        .clipShape(.rect(cornerRadius: 6))
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
