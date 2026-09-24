// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Search across the library, as a reusable list.
///
/// Queries the server (`GET /api/v1/search`), which covers titles, people,
/// dialogue and book text — more than a title match. Debounced so it does not
/// fire on every keystroke, and it falls back to filtering the already-loaded
/// catalogue when the server cannot be reached, so search still works with a
/// flaky connection.
///
/// This is the body only (no NavigationStack), so it drops into the search
/// overlay the persistent header presents. It carries its own `.searchable`.
struct SearchResultsList: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback

    @State private var term = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var addingToPlaylist: MediaItem?

    var body: some View {
        List(results) { item in
            Button {
                if item.type == .music { playback.play([item]) }
            } label: {
                HStack(spacing: 12) {
                    Artwork(item: item, size: 44, aspect: item.type == .music ? 1 : 1.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
                        }
                    }
                    Spacer()

                    // The same actions a track carries everywhere else —
                    // play next, queue, playlist, download — rather than a
                    // result you can only play (S-361).
                    Menu {
                        TrackActions(item: item) { addingToPlaylist = item }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(SoundChexTheme.ink500)
                            .frame(width: 32, height: 32)
                            .contentShape(.rect)
                    }
                    // Plain, so tapping the kebab does not also fire the row's
                    // own play button — they share a row (S-344).
                    .buttonStyle(.plain)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(SoundChexTheme.base900)
        }
        .sheet(item: $addingToPlaylist) { item in
            AddToPlaylistSheet(item: item)
        }
        .listStyle(.plain)
        .overlay {
            if term.count < 2 {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
            } else if isSearching && results.isEmpty {
                ProgressView().tint(SoundChexTheme.accent)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: term)
            }
        }
        .background(SoundChexTheme.base900)
        .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Songs, films, books…")
        .onChange(of: term) { _, newValue in
            runSearch(newValue)
        }
    }

    /// Debounced search: the cached catalogue at once, the server to refine it.
    ///
    /// The order used to be the other way round, which meant that offline —
    /// airplane mode, out of service, or the server simply down — every search
    /// waited out the request's 20-second timeout before falling back, and
    /// looked like search was broken rather than slow (S-336).
    private func runSearch(_ query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }

        // Answer from what the device already holds, before anything is
        // awaited. Offline this is the whole answer; online it is what the
        // server's reply replaces a moment later.
        results = store.search(trimmed)

        searchTask = Task {
            // Wait out a burst of typing before hitting the network.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            guard let api = session.api else { return }

            isSearching = true
            defer { isSearching = false }

            // The server searches fields the device does not cache, so its
            // answer is better when it arrives — but never at the cost of the
            // one already on screen.
            guard let found = try? await api.search(trimmed), !Task.isCancelled else { return }

            results = found
        }
    }
}
