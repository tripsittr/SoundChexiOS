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
    }
}
