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
    let item: MediaItem

    @State private var playlists: [Playlist] = []
    @State private var loading = true
    @State private var newName = ""
    @State private var creating = false
    @State private var message: String?

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
            .navigationTitle("Add to playlist")
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
    }

    private func load() async {
        loading = true
        // Through the shared store, so this sheet and the grid cannot disagree
        // about what playlists exist (S-372).
        await store.reload()
        playlists = store.playlists
        loading = false
    }

    private func add(to playlist: Playlist) {
        Task {
            do {
                try await session.api?.addToPlaylist(playlist.id, itemID: item.id)
                // The card shows a track count and a mosaic of its first few
                // covers; both just changed.
                await store.reload()
                playlists = store.playlists
                flash("Added to \(playlist.name)")
                dismiss()
            } catch { flash("Couldn't add") }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        creating = true
        Task {
            do {
                if let created = try await session.api?.createPlaylist(name: name) {
                    try await session.api?.addToPlaylist(created.id, itemID: item.id)
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
