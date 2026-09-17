import SwiftUI

/// A horizontal rail of posters, matching the web `.rail`: a bold heading with an
/// optional "View all →", then a snap-scrolling row of tiles.
struct Rail: View {
    let title: String
    let items: [MediaItem]
    var onTap: (MediaItem) -> Void = { _ in }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in
                            Button { onTap(item) } label: {
                                PosterTile(item: item, width: 144)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
            .padding(.vertical, 8)
        }
    }
}
