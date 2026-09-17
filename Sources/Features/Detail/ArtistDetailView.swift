import SwiftUI

/// An artist: their albums in a grid. Tapping an album opens it.
struct ArtistDetailView: View {
    let artist: LibraryStore.Artist

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(artist.albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
                            Text(album.title).font(.subheadline)
                                .foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                            Text("\(album.tracks.count) songs").font(.caption)
                                .foregroundStyle(SoundChexTheme.ink500)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
