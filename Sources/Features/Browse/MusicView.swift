import SwiftUI

/// The Music tab: Songs / Albums / Artists, chosen with a segmented control —
/// the native equivalent of the web music sub-nav. The picker lives in the
/// navigation bar so there is no stray empty header above the content.
struct MusicView: View {
    @Environment(LibraryStore.self) private var store
    @State private var section: Section = .songs

    enum Section: String, CaseIterable { case songs = "Songs", albums = "Albums", artists = "Artists" }

    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Music")
                .navigationBarTitleDisplayMode(.inline)
                .background(SoundChexTheme.base900)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("", selection: $section) {
                            ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SoundChexTheme.base900)
        } else {
            switch section {
            case .songs:
                let songs = store.items(of: .music)
                List(Array(songs.enumerated()), id: \.element.id) { pair in
                    SongRow(item: pair.element, queue: songs, index: pair.offset)
                        .listRowBackground(SoundChexTheme.base900)
                }
                .listStyle(.plain)

            case .albums:
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 20) {
                        ForEach(store.albums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album)
                            } label: { albumCell(album) }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(SoundChexTheme.base900)

            case .artists:
                List(store.artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: artist.artwork) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700
                            }
                            .frame(width: 44, height: 44).clipShape(.circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                                Text("\(artist.albums.count) albums").font(.caption)
                                    .foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                    }
                    .listRowBackground(SoundChexTheme.base900)
                }
                .listStyle(.plain)
            }
        }
    }

    private func albumCell(_ album: LibraryStore.Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
            Text(album.title).font(.subheadline).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
        }
    }
}
