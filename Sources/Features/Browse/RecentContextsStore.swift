// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// What you last played, remembered by where you played it *from* (S-392).
///
/// The distinction is the whole point. A history of tracks would say you
/// listened to "Kill Yourself Part III"; what you actually did was put on an
/// artist, and that artist is what you want back on the landing page. So the
/// unit recorded here is the context playback started from — an artist, an
/// album, a playlist — and a loose song only when a song is genuinely what
/// was picked.
///
/// This is client-side because the server cannot answer it. `media_plays` has
/// a `source` column, but it holds a surface name ("browse", "home") rather
/// than an identity, and the client's only playback ping is
/// `POST /items/{id}/progress`, which sends position and duration and nothing
/// about where the track came from. Recording context server-side would mean
/// an API change on both sides to answer a question that is purely about this
/// device's own recent history.
@MainActor
@Observable
final class RecentContextsStore {
    /// One remembered context. Stored by id rather than by value because
    /// `LibraryStore.Album` and `.Artist` are computed fresh from `items` on
    /// every access — there is no stored object to hold on to, and a cached
    /// copy would go stale the moment the library re-synced.
    struct Entry: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case artist, album, playlist, song }

        let kind: Kind
        /// `Album.id` ("artist|albumKey"), `Artist.id` (the name), the
        /// playlist's `Int` id as a string, or the track's id as a string.
        let id: String
        let playedAt: Date
    }

    /// Newest first.
    private(set) var entries: [Entry] = []

    /// Enough to fill the landing page's rails without the list growing
    /// without bound in UserDefaults.
    private let limit = 24

    private let defaults: UserDefaults
    nonisolated private static let storageKey = "library.recentContexts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()

        observer = NotificationCenter.default.addObserver(
            forName: Self.storageClearedNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.entries = [] }
        }
    }

    /// Held so the block observer outlives `init`. Not removed in `deinit`:
    /// this store is created once at app launch and lives as long as the app,
    /// and a `deinit` touching it cannot satisfy Swift 6's isolation rules.
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// Records a context, moving it to the front if it is already known.
    ///
    /// De-duplicating by identity rather than appending keeps the page useful:
    /// playing one album four times in an evening should leave one entry at
    /// the top, not four that crowd everything else out.
    func record(_ kind: Entry.Kind, id: String) {
        entries.removeAll { $0.kind == kind && $0.id == id }
        entries.insert(Entry(kind: kind, id: id, playedAt: Date()), at: 0)

        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }

        save()
    }

    /// The most recent entries of one kind.
    func recent(_ kind: Entry.Kind, limit: Int) -> [Entry] {
        Array(entries.filter { $0.kind == kind }.prefix(limit))
    }

    /// Forgets everything. Called on sign-out and on a server change, next to
    /// `LibraryStore.clearCache()` — recent history belongs to the account
    /// that made it, and leaving one user's listening on the page for the
    /// next one would be a small betrayal.
    func clear() {
        entries = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Wipes the stored history without needing the instance — for
    /// `LibraryStore.clearCache()`, which is static and runs on sign-out.
    ///
    /// The notification is what makes it stick. Removing the key alone would
    /// leave the live store's `entries` populated, so the next account would
    /// keep seeing the last one's listening until the app was force-quit —
    /// the cleared page is the whole point of clearing it.
    nonisolated static func clearStorage() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: storageClearedNotification, object: nil)
    }

    nonisolated static let storageClearedNotification = Notification.Name("RecentContextsStore.cleared")

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }

        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
