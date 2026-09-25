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
    @Environment(RecentContextsStore.self) private var recents
    let item: MediaItem
    var queue: [MediaItem] = []
    var index: Int = 0
    /// Set only where the row is *in* a playlist (S-376).
    var onRemoveFromPlaylist: (() -> Void)?
    /// What playing this row means you played (S-392). The row is shared
    /// between the Songs list and the playlist page, and the two record
    /// different things: a song picked out of the library is a song, the same
    /// row inside a playlist is that playlist. Defaults to the loose song,
    /// which is what every other caller is.
    var playContext: RecentContextsStore.Entry?

    @State private var addingToPlaylist = false
    @State private var editing = false
    @State private var confirmingReview = false
    @State private var reporting = false

    /// Whether this row is the track playing now — drives the equalizer overlay
    /// and the accent title.
    private var isCurrent: Bool { playback.current?.id == item.id }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let playContext {
                    recents.record(playContext.kind, id: playContext.id)
                } else {
                    recents.record(.song, id: String(item.id))
                }
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
                             onEdit: { editing = true },
                             onSendForReview: { confirmingReview = true })
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
        // Says what reporting does before asking why, so a track is never
        // hidden by one stray tap in the menu (S-400).
        .confirmationDialog(
            "Send “\(item.title)” for review?",
            isPresented: $confirmingReview,
            titleVisibility: .visible,
        ) {
            Button("Send for review") { reporting = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be hidden from your library until someone has "
                + "looked at it. Nothing is deleted — it comes back once the "
                + "review is cleared.")
        }
        .sheet(isPresented: $reporting) {
            SendForReviewSheet(item: item)
                .presentationDetents([.large])
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
    /// Set where the row can be reported. The closure raises the confirmation;
    /// this menu only asks for it (S-400).
    var onSendForReview: (() -> Void)?

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

        // Reporting hides the item from the library until someone clears it
        // (S-396), so this never fires straight from the menu: the caller
        // raises a confirmation first that says exactly that (S-400).
        if let onSendForReview {
            Button {
                onSendForReview()
            } label: {
                Label("Send for review", systemImage: "exclamationmark.triangle")
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
