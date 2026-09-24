// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

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
    @Environment(ThemeStore.self) private var theme
    @Environment(DownloadStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    let item: MediaItem
    var queue: [MediaItem] = []
    var index: Int = 0
    /// Set only where the row is *in* a playlist (S-376).
    var onRemoveFromPlaylist: (() -> Void)?

    @State private var addingToPlaylist = false
    @State private var editing = false

    /// Whether this row is the track playing now — drives the equalizer overlay
    /// and the accent title.
    private var isCurrent: Bool { playback.current?.id == item.id }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.play(queue.isEmpty ? [item] : queue, startAt: index)
            } label: {
                HStack(spacing: 12) {
                    // The current track shows an animated equalizer over its
                    // cover — the Spotify "now playing" tell (S-288).
                    // One component for the now-playing tell, shared with
                    // search, albums and artists (S-362).
                    TrackArtwork(item: item, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(isCurrent ? SoundChexTheme.accent : SoundChexTheme.ink100)
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
            // Offline, a track this device does not hold cannot play: dim it
            // and stop it taking the tap (S-362). The kebab stays live.
            .playableRow(Playability.canPlay(item, downloads: downloads, online: connectivity.isOnline))

            // Persistent download control, like the web row.
            DownloadButton(item: item, size: 18)

            // The kebab: the same actions as the swipes, for discoverability.
            Menu {
                TrackActions(item: item,
                             onAddToPlaylist: { addingToPlaylist = true },
                             onRemoveFromPlaylist: onRemoveFromPlaylist,
                             onEdit: { editing = true })
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(SoundChexTheme.ink500)
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
        }
        // Swipe right → add to queue; swipe left → add to playlist.
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
                addingToPlaylist = true
            } label: {
                Label("Playlist", systemImage: "music.note.list")
            }
            .tint(SoundChexTheme.base600)
            Button {
                playback.playNext(item)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(SoundChexTheme.ink600)
        }
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(item: item)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
        .sheet(isPresented: $editing) {
            AdminItemEditView(itemID: item.id)
                .soundchexTheme(theme)
        }
    }
}

/// The per-track action set, shared by the kebab menu and the now-playing page.
///
/// Add-to-playlist is a callback rather than a self-contained action because a
/// menu item cannot present a sheet — the owning row does, when this asks.
struct TrackActions: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadStore.self) private var downloads
    @Environment(Connectivity.self) private var connectivity
    @Environment(Session.self) private var session
    let item: MediaItem
    var onAddToPlaylist: (() -> Void)?
    /// Set only where the row is *in* a playlist, so the action appears there
    /// and nowhere else (S-376).
    var onRemoveFromPlaylist: (() -> Void)?
    var onEdit: (() -> Void)?

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

        if let onAddToPlaylist {
            Button {
                onAddToPlaylist()
            } label: {
                Label("Add to playlist", systemImage: "music.note.list")
            }
        }

        if let onRemoveFromPlaylist {
            Button(role: .destructive) {
                onRemoveFromPlaylist()
            } label: {
                Label("Remove from playlist", systemImage: "minus.circle")
            }
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

        // Admin-only: edit the item's metadata.
        if session.isAdmin, let onEdit {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}
