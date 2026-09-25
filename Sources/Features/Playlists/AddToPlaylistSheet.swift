// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Pick a playlist to add a track to — or make a new one. Shown from the kebab
/// and the swipe-left action.
struct AddToPlaylistSheet: View {
    @Environment(Session.self) private var session
    // Shared with the playlists grid, so one made here shows up there without
    // waiting for a relaunch (S-372).
    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The tracks to add.
    ///
    /// A set rather than one, so a whole album or an artist's whole catalogue
    /// goes in with one action instead of a track at a time (S-385).
    let items: [MediaItem]

    /// One track — the row kebab's case, which is most of them.
    init(item: MediaItem) {
        self.items = [item]
    }

    init(items: [MediaItem]) {
        self.items = items
    }

    @State private var playlists: [Playlist] = []
    @State private var loading = true
    @State private var newName = ""
    @State private var creating = false
    @State private var message: String?
    /// The playlist a duplicate add is waiting on an answer for (S-373).
    @State private var alreadyIn: Playlist?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist", text: $newName)
                            .textInputAutocapitalization(.words)
                        Button("Create") { create() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                    }
                }

                Section("Your playlists") {
                    if loading {
                        ProgressView()
                    } else if playlists.isEmpty {
                        Text("No playlists yet").foregroundStyle(SoundChexTheme.ink500)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "music.note.list")
                                    Spacer()
                                    if let count = playlist.count {
                                        Text("\(count)").foregroundStyle(SoundChexTheme.ink500)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            // Says how many are going in, so "Add to playlist" from an album
            // does not look like it will add only the track you tapped.
            .navigationTitle(items.count == 1 ? "Add to playlist" : "Add \(items.count) to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.subheadline).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(SoundChexTheme.base700, in: .capsule)
                        .padding(.bottom, 24)
                }
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Already in \(alreadyIn?.name ?? "this playlist")",
            isPresented: Binding(get: { alreadyIn != nil }, set: { if !$0 { alreadyIn = nil } }),
            titleVisibility: .visible,
        ) {
            Button("Move to the end") {
                if let playlist = alreadyIn {
                    alreadyIn = nil
                    add(to: playlist, moveToEnd: true)
                }
            }
            Button("Cancel", role: .cancel) { alreadyIn = nil }
        } message: {
            Text("This song is already in the playlist. A playlist can't list the same song twice, but it can be moved to the end.")
        }
    }

    private func load() async {
        loading = true
        // Through the shared store, so this sheet and the grid cannot disagree
        // about what playlists exist (S-372).
        await store.reload()
        playlists = store.playlists
        loading = false
    }

    private func add(to playlist: Playlist, moveToEnd: Bool = false) {
        Task {
            var added = 0
            var alreadyThere = 0
            var failed = 0

            for track in items {
                do {
                    try await session.api?.addToPlaylist(playlist.id, itemID: track.id, moveToEnd: moveToEnd)
                    added += 1
                } catch APIClient.APIError.alreadyInPlaylist {
                    alreadyThere += 1
                } catch {
                    failed += 1
                }
            }

            // One track already there is a question worth asking — a playlist
            // cannot list the same song twice, so the only thing adding again
            // can do is move it to the end (S-373). For a whole album it is
            // not: nobody wants "move to the end?" forty times, and the tracks
            // are already where they should be.
            if items.count == 1, alreadyThere == 1, !moveToEnd {
                alreadyIn = playlist

                return
            }

            // The card shows a track count and a mosaic of its first few
            // covers; both just changed.
            await store.reload()
            playlists = store.playlists

            flash(summary(added: added, alreadyThere: alreadyThere, failed: failed, playlist: playlist, moved: moveToEnd))

            if failed < items.count {
                dismiss()
            }
        }
    }

    /// What to say after adding, in the terms the action was taken in.
    private func summary(added: Int, alreadyThere: Int, failed: Int, playlist: Playlist, moved: Bool) -> String {
        if added == 0 && alreadyThere > 0 {
            return alreadyThere == 1 ? "Already in \(playlist.name)" : "All \(alreadyThere) already there"
        }

        if added == 0 {
            return "Couldn't add"
        }

        if moved {
            return "Moved to the end of \(playlist.name)"
        }

        let what = added == 1 ? "Added" : "Added \(added)"
        let rest = alreadyThere > 0 ? " — \(alreadyThere) already there" : ""

        return "\(what) to \(playlist.name)\(rest)"
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        creating = true
        Task {
            do {
                if let created = try await session.api?.createPlaylist(name: name) {
                    for track in items {
                        try await session.api?.addToPlaylist(created.id, itemID: track.id)
                    }
                    // The grid caches its list and only loads it once, so a
                    // playlist made here stayed invisible until the app was
                    // relaunched — it looked as though nothing had been
                    // created at all (S-372).
                    await store.reload()
                    playlists = store.playlists
                    flash("Added to \(name)")
                    dismiss()
                }
            } catch { flash("Couldn't create") }
            creating = false
        }
    }

    private func flash(_ text: String) {
        message = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            message = nil
        }
    }
}
