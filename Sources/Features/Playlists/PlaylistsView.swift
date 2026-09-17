import SwiftUI

/// A store of the account's playlists, shared by the Music pill and the Settings
/// entry so both show the same list and a change in one is seen in the other.
@MainActor
@Observable
final class PlaylistStore {
    private(set) var playlists: [Playlist] = []
    private(set) var loading = false

    private var api: APIClient?
    private var loadedOnce = false

    func attach(api: APIClient?) { self.api = api }

    func loadIfNeeded() async {
        guard !loadedOnce else { return }
        await reload()
    }

    func reload() async {
        loading = playlists.isEmpty
        playlists = (try? await api?.playlists()) ?? playlists
        loadedOnce = true
        loading = false
    }
}

/// The playlists grid — the Music tab's Playlists pill. Cover cards in a grid,
/// with a "New playlist" tile first, Spotify/Apple style.
struct PlaylistsGrid: View {
    @Environment(Session.self) private var session
    @State private var store = PlaylistStore()
    @State private var creating = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                Button { creating = true } label: { newTile }
                    .buttonStyle(.plain)

                ForEach(store.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist) { Task { await store.reload() } }
                    } label: {
                        PlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(SoundChexTheme.base900)
        .overlay {
            if store.loading && store.playlists.isEmpty {
                ProgressView().tint(SoundChexTheme.accent)
            }
        }
        .task {
            store.attach(api: session.api)
            await store.loadIfNeeded()
        }
        .sheet(isPresented: $creating) {
            EditPlaylistSheet(playlist: nil) { Task { await store.reload() } }
                .presentationDetents([.medium])
        }
    }

    private var newTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: SoundChexTheme.radiusPoster)
                .fill(SoundChexTheme.base700)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(SoundChexTheme.ink400)
                )
            Text("New playlist").font(.subheadline).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
            Text("Create").font(.caption).foregroundStyle(SoundChexTheme.ink500)
        }
    }
}

/// One playlist card: cover (image or track-art mosaic) over name + count.
struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaylistCover(artworkURL: playlist.artworkURL, mosaic: [])
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
            Text(playlist.name).font(.subheadline).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
            if let count = playlist.count {
                Text("\(count) song\(count == 1 ? "" : "s")").font(.caption)
                    .foregroundStyle(SoundChexTheme.ink500)
            }
        }
    }
}

/// A playlist cover: its uploaded image when it has one, otherwise a 2×2 mosaic
/// of the first four tracks' covers (Spotify's fallback), or a note glyph when
/// there is nothing to show yet.
struct PlaylistCover: View {
    let artworkURL: URL?
    /// Track artwork URLs for the mosaic fallback, in order.
    let mosaic: [URL]

    var body: some View {
        if let artworkURL {
            CachedImage(url: artworkURL) { $0.resizable().scaledToFill() } placeholder: { base }
        } else if !mosaic.isEmpty {
            mosaicGrid
        } else {
            base.overlay(
                Image(systemName: "music.note.list")
                    .font(.system(size: 34))
                    .foregroundStyle(SoundChexTheme.ink500))
        }
    }

    private var base: some View { SoundChexTheme.base700 }

    private var mosaicGrid: some View {
        GeometryReader { geo in
            let side = geo.size.width / 2
            let tiles = Array(mosaic.prefix(4))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    cell(tiles.indices.contains(0) ? tiles[0] : nil, side)
                    cell(tiles.indices.contains(1) ? tiles[1] : nil, side)
                }
                HStack(spacing: 0) {
                    cell(tiles.indices.contains(2) ? tiles[2] : nil, side)
                    cell(tiles.indices.contains(3) ? tiles[3] : nil, side)
                }
            }
        }
    }

    private func cell(_ url: URL?, _ side: CGFloat) -> some View {
        Group {
            if let url {
                CachedImage(url: url) { $0.resizable().scaledToFill() } placeholder: { base }
            } else {
                base
            }
        }
        .frame(width: side, height: side)
        .clipped()
    }
}
