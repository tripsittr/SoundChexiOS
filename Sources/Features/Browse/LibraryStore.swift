// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Observation

/// The device's copy of the catalogue, loaded once and filtered by every screen.
///
/// One fetch of `/api/v1/library` fills this; the tabs read from it rather than
/// each hitting the network. It is persisted to disk for offline use and kept in
/// step with `/library/delta`: after the first full fetch, refreshes send the
/// last `synced_at` and apply only what changed, the way the web mirror does.
@MainActor
@Observable
final class LibraryStore {
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private var api: APIClient?
    private var hasLoaded = false

    /// When the catalogue was last synced with the server, this run.
    ///
    /// `loadIfNeeded()` guards on `hasLoaded`, so it syncs once per launch —
    /// which is right for a screen the user opens and leaves, and wrong for an
    /// app left open all evening. A correction made on the server (a fixed
    /// album, a merged duplicate) then sat unseen until the app was killed and
    /// reopened (S-386).
    private var lastSyncedAt: Date?

    /// How stale the catalogue may get before a screen appearing refreshes it.
    ///
    /// A delta with nothing to report is a few hundred bytes, so this is cheap
    /// — but not free, and the library does not change minute to minute.
    private static let refreshInterval: TimeInterval = 5 * 60

    /// The server's `synced_at` from the last successful fetch, sent back as the
    /// delta baseline. Persisted so a relaunch can sync incrementally rather than
    /// re-downloading the whole catalogue. UserDefaults, not the cache file, so a
    /// cleared cache also clears the baseline and forces a clean full fetch.
    private static let syncedAtKey = "library.syncedAt"
    private var syncedAt: String? {
        get { UserDefaults.standard.string(forKey: Self.syncedAtKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncedAtKey) }
    }

    /// Where the catalogue is cached on disk, so it browses offline and a launch
    /// shows something immediately rather than waiting on the network.
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    func attach(api: APIClient?) {
        self.api = api
    }

    /// On first appearance, show the disk cache at once (so the app is usable
    /// offline and a launch is instant), then refresh from the network.
    func loadIfNeeded() async {
        guard !isLoading else { return }

        // Already loaded this run: sync again only if it has gone stale, so
        // moving between tabs costs nothing but an evening's use still picks
        // up what changed on the server (S-386).
        if hasLoaded {
            await refreshIfStale()

            return
        }

        loadFromDisk()
        await load()
    }

    /// Syncs if the catalogue has not been refreshed recently.
    ///
    /// Called when a library screen appears and when the app returns from the
    /// background — the two moments a stale list is about to be looked at.
    func refreshIfStale() async {
        guard hasLoaded, !isLoading else { return }

        if let last = lastSyncedAt, Date().timeIntervalSince(last) < Self.refreshInterval {
            return
        }

        await load()
    }

    func load() async {
        guard let api else { return }

        // Only show the spinner when there is nothing cached to show meanwhile.
        isLoading = items.isEmpty
        loadError = nil

        do {
            // With a baseline and a non-empty cache, sync incrementally; a full
            // fetch on every launch would move ~0.8 MB to replace what is almost
            // always unchanged.
            if let since = syncedAt, !items.isEmpty {
                try await applyDelta(since: since, api: api)
            } else {
                try await fullFetch(api: api)
            }
            hasLoaded = true
            lastSyncedAt = Date()
        } catch {
            // Offline with a cache is not an error — the cached library stands.
            if items.isEmpty {
                loadError = (error as? APIClient.APIError)?.errorDescription
                    ?? "Could not load your library."
            }
        }

        isLoading = false
    }

    /// Replaces the whole catalogue from the server and records the new baseline.
    private func fullFetch(api: APIClient) async throws {
        let response = try await api.library()
        items = response.items
        syncedAt = response.syncedAt
        saveToDisk()
    }

    /// Fetches only what changed since `since`, merges updates, drops removed
    /// ids, and advances the baseline. Falls back to a full fetch if the server
    /// rejects the baseline (e.g. a 422 on a malformed date after a data reset).
    private func applyDelta(since: String, api: APIClient) async throws {
        let delta: LibraryDeltaResponse
        do {
            delta = try await api.libraryDelta(since: since, knownIDs: items.map(\.id))
        } catch APIClient.APIError.http(let status) where status == 422 {
            try await fullFetch(api: api)
            return
        }

        if !delta.items.isEmpty || !delta.removedIds.isEmpty {
            var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for updated in delta.items { byID[updated.id] = updated }
            for removed in delta.removedIds { byID.removeValue(forKey: removed) }
            // Keep id order — the server orders by id and "Recently added" and the
            // hero read the tail/head of that order, which a dictionary loses.
            items = byID.values.sorted { $0.id < $1.id }
            saveToDisk()
        }

        // Advance the baseline even when nothing changed, so the next window is
        // measured from this sync rather than re-reporting the same span.
        if let newSynced = delta.syncedAt { syncedAt = newSynced }
    }

    /// Fills from the disk cache if the network copy has not loaded yet.
    private func loadFromDisk() {
        guard items.isEmpty,
              let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode([MediaItem].self, from: data) else { return }
        items = cached
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.cacheURL)
        }
    }

    /// Drops the cached library and its sync baseline — for sign-out / change
    /// server, so the next account starts from a clean full fetch.
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        UserDefaults.standard.removeObject(forKey: syncedAtKey)
        // Recent contexts are this account's listening too (S-392). Cleared
        // here rather than at the sign-out call sites so a future one cannot
        // forget: whoever drops the library drops the history with it.
        RecentContextsStore.clearStorage()

        // Pending expiry warnings belong to the account that made them
        // (S-405). The next person's phone should not announce the last
        // person's downloads.
        Task { @MainActor in ExpiryNotifications.cancelAll() }
    }

    // MARK: - Filtered views

    func items(of type: MediaType) -> [MediaItem] {
        items
            .filter { $0.type == type }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Top-level items of a type — for shows and albums we don't want every
    /// episode/track in the grid, only the parents. An item with no `parentID`
    /// is a top-level one.
    func topLevel(of type: MediaType) -> [MediaItem] {
        items(of: type).filter { $0.parentID == nil }
    }

    /// The children of an item (a show's episodes), by parent id, in order.
    func children(of parentID: Int) -> [MediaItem] {
        items
            .filter { $0.parentID == parentID }
            .sorted {
                let a = ($0.meta?.seasonNumber ?? 0, $0.meta?.episodeNumber ?? 0)
                let b = ($1.meta?.seasonNumber ?? 0, $1.meta?.episodeNumber ?? 0)
                return a < b
            }
    }

    // MARK: - Music grouping (albums, artists)

    /// The album key standing in for "no album", so an artist's loose tracks
    /// gather into one entry rather than one tile each (S-386).
    private static let singlesKey = "\u{0000}singles"

    /// One album: its tracks, in disc/track order.
    struct Album: Identifiable, Hashable {
        let id: String            // artist|albumKey, so variants merge but two different albums of a name don't
        let title: String
        let artist: String
        let tracks: [MediaItem]
        var artwork: URL? { tracks.first?.artwork }
    }

    /// Albums, grouped from the music tracks by primary artist + album key.
    ///
    /// Grouping on the *primary* artist (not the raw credit) keeps every track of
    /// an album together even when some are tagged "Artist, Someone", and on the
    /// canonical *album key* (not the raw title) so edition/punctuation variants
    /// of one album — "Album" and "Album (Deluxe)" — collapse into one rather than
    /// showing twice (S-308).
    var albums: [Album] {
        let music = items(of: .music)
        let groups = Dictionary(grouping: music) { item in
            let artist = item.meta?.groupingArtist ?? ""

            // A track with no album is a single, not an album of one. Falling
            // back to the *title* gave each one its own tile labelled
            // "Unknown album" — 83 of them on a real library — so they are
            // gathered per artist instead (S-386).
            guard let album = item.meta?.groupingAlbum, !album.isEmpty else {
                return "\(artist)|\(Self.singlesKey)"
            }

            return "\(artist)|\(album)"
        }
        return groups.compactMap { key, tracks -> Album? in
            guard let first = tracks.first else { return nil }
            let sorted = tracks.sorted {
                ($0.meta?.discNumber ?? 0, $0.meta?.trackNumber ?? 0)
                    < ($1.meta?.discNumber ?? 0, $1.meta?.trackNumber ?? 0)
            }
            // Show the plainest spelling in the group — the shortest album title,
            // which is the one without a "(Deluxe)" / "(Remastered)" tail.
            let title = tracks
                .compactMap { $0.meta?.album }
                .filter { !$0.isEmpty }
                .min { $0.count < $1.count }
                // No album anywhere in the group: these are the artist's
                // loose tracks, and "Singles" says that where "Unknown album"
                // only said something had gone wrong.
                ?? "Singles"

            return Album(
                id: key,
                title: title,
                artist: first.meta?.groupingArtist ?? "Unknown artist",
                tracks: sorted
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// One artist: their albums.
    struct Artist: Identifiable, Hashable {
        let id: String            // the artist name
        let name: String
        let albums: [Album]
        var artwork: URL? { albums.first?.artwork }
        var trackCount: Int { albums.reduce(0) { $0 + $1.tracks.count } }
    }

    /// Artists, grouped from the albums.
    var artists: [Artist] {
        let groups = Dictionary(grouping: albums) { $0.artist }
        return groups.map { name, albums in
            Artist(id: name, name: name, albums: albums.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Home

    /// The hero item — the most recently added top-level thing with artwork.
    var heroItem: MediaItem? {
        items
            .filter { $0.parentID == nil && $0.artwork != nil }
            .first
    }

    /// The home rails: a "Recently added" mix, then one row per type. Derived
    /// from the loaded catalogue, the way the web home composes its rows.
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let items: [MediaItem]
    }

    var homeRows: [Row] {
        var rows: [Row] = []

        let recent = items.filter { $0.parentID == nil }.prefix(20)
        if !recent.isEmpty { rows.append(Row(title: "Recently added", items: Array(recent))) }

        for (type, label) in [(MediaType.music, "Music"), (.movie, "Movies"),
                              (.show, "Shows"), (.book, "Books")] {
            let ofType = topLevel(of: type).prefix(20)
            if !ofType.isEmpty { rows.append(Row(title: label, items: Array(ofType))) }
        }

        return rows
    }

    func search(_ term: String) -> [MediaItem] {
        let needle = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }

        return items.filter { item in
            item.title.lowercased().contains(needle)
                || (item.subtitle?.lowercased().contains(needle) ?? false)
                || (item.meta?.artist?.lowercased().contains(needle) ?? false)
                || (item.meta?.album?.lowercased().contains(needle) ?? false)
                || (item.meta?.author?.lowercased().contains(needle) ?? false)
        }
    }
}
