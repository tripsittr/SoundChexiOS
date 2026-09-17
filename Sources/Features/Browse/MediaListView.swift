import SwiftUI

/// A scrolling list of items — songs, mostly, where a row-per-track reads better
/// than a grid.
struct MediaListView: View {
    @Environment(LibraryStore.self) private var store
    let type: MediaType
    let title: String

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.loadError, store.items.isEmpty {
                    ContentUnavailableView("Couldn't load", systemImage: "wifi.slash", description: Text(error))
                } else {
                    let songs = store.items(of: type)
                    List(Array(songs.enumerated()), id: \.element.id) { pair in
                        SongRow(item: pair.element, queue: songs, index: pair.offset)
                            .listRowBackground(SoundChexTheme.base900)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .background(SoundChexTheme.base900)
        }
    }
}

/// One song row: artwork, title, artist, and a tap to play. Tapping starts the
/// whole list from this row, so the rest of the screen queues behind it.
struct SongRow: View {
    @Environment(PlaybackController.self) private var playback
    let item: MediaItem
    var queue: [MediaItem] = []
    var index: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.play(queue.isEmpty ? [item] : queue, startAt: index)
            } label: {
                HStack(spacing: 12) {
                    Artwork(item: item, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(SoundChexTheme.ink100)
                            .lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(SoundChexTheme.ink500)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // The kebab: the same actions as the swipes, for discoverability.
            Menu {
                TrackActions(item: item)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(SoundChexTheme.ink500)
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
        }
        // Swipe right → add to queue; swipe left → play next. (Add to playlist
        // joins the left swipe once the playlist API lands — IOS-19.)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                playback.addToQueue(item)
            } label: {
                Label("Queue", systemImage: "text.append")
            }
            .tint(SoundChexTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                playback.playNext(item)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(SoundChexTheme.base600)
        }
    }
}

/// The per-track action set, shared by the kebab menu and (later) the context
/// menu. Playlist actions are added with the playlist API (IOS-19).
struct TrackActions: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadStore.self) private var downloads
    let item: MediaItem

    var body: some View {
        Button {
            playback.playNext(item)
        } label: {
            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            playback.addToQueue(item)
        } label: {
            Label("Add to queue", systemImage: "text.append")
        }

        if downloads.isStored(item.id) {
            Button(role: .destructive) {
                downloads.remove(item.id)
            } label: {
                Label("Remove download", systemImage: "trash")
            }
        } else {
            Button {
                downloads.download(item)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
        // "Add to playlist" appears here once the playlist API is wired (IOS-19).
    }
}
