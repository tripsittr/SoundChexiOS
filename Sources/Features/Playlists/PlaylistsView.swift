import SwiftUI

/// The account's playlists, and a playlist's tracks. Tapping a playlist opens it;
/// tapping a track plays the playlist from there.
struct PlaylistsView: View {
    @Environment(Session.self) private var session
    @State private var playlists: [Playlist] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(SoundChexTheme.accent)
                } else if playlists.isEmpty {
                    ContentUnavailableView("No playlists",
                                           systemImage: "music.note.list",
                                           description: Text("Add a song to a playlist from its ⋯ menu."))
                } else {
                    List(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            HStack {
                                Label(playlist.name, systemImage: "music.note.list")
                                    .foregroundStyle(SoundChexTheme.ink100)
                                Spacer()
                                if let count = playlist.count {
                                    Text("\(count)").foregroundStyle(SoundChexTheme.ink500)
                                }
                            }
                        }
                        .listRowBackground(SoundChexTheme.base900)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Playlists")
            .background(SoundChexTheme.base900)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        playlists = (try? await session.api?.playlists()) ?? []
        loading = false
    }
}

/// One playlist's tracks, playable as a queue.
struct PlaylistDetailView: View {
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback
    let playlist: Playlist

    @State private var tracks: [MediaItem] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(SoundChexTheme.accent)
            } else {
                List(Array(tracks.enumerated()), id: \.element.id) { pair in
                    SongRow(item: pair.element, queue: tracks, index: pair.offset)
                        .listRowBackground(SoundChexTheme.base900)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        .background(SoundChexTheme.base900)
        .task {
            let detail = try? await session.api?.playlist(playlist.id)
            tracks = detail?.items ?? []
            loading = false
        }
    }
}
