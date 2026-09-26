// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Suggestions for the Your Library page (S-413).
///
/// Built from what the device already holds — the mirrored catalogue's
/// `lastPlayedAt` and the recent-contexts store — rather than from a server
/// endpoint, because neither exists yet and the page is worth improving now.
/// When the real recommender lands (S-289) these become the fallback, or the
/// shape the server fills.
///
/// Every shelf here is honest about its own emptiness: a library with no play
/// history produces fewer shelves rather than empty ones, and a shelf with one
/// item is not worth a header, so it is dropped. The page should never show a
/// title over nothing.
@MainActor
enum LibraryShelves {
    /// One suggestion row.
    struct Shelf: Identifiable {
        let id: String
        let title: String
        /// Why this is being suggested, shown under the title. Recommendations
        /// that do not say why read as arbitrary.
        let reason: String?
        let albums: [LibraryStore.Album]
    }

    /// A shelf needs this many items to earn its header.
    private static let minimum = 2

    /// How many shelves the page shows at once, so it stays a page rather than
    /// an endless scroll of near-identical rows.
    private static let maxShelves = 4

    static func build(
        store: LibraryStore,
        recents: RecentContextsStore,
        limit: Int = 10,
    ) -> [Shelf] {
        var shelves: [Shelf] = []

        let albums = store.albums

        if let shelf = moreFromRecentArtist(albums: albums, recents: recents, limit: limit) {
            shelves.append(shelf)
        }

        if let shelf = notHeardInAWhile(albums: albums, limit: limit) {
            shelves.append(shelf)
        }

        if let shelf = pickUpWhereYouLeftOff(albums: albums, limit: limit) {
            shelves.append(shelf)
        }

        return Array(shelves.prefix(maxShelves))
    }

    /// Other albums by the artist you played most recently.
    ///
    /// The strongest signal the device has: you chose that artist minutes ago,
    /// so the rest of their work is the least speculative suggestion available.
    private static func moreFromRecentArtist(
        albums: [LibraryStore.Album],
        recents: RecentContextsStore,
        limit: Int,
    ) -> Shelf? {
        // The most recent artist *or* album context — playing an album is just
        // as much a statement about its artist.
        let artistName = recents.entries.lazy.compactMap { entry -> String? in
            switch entry.kind {
            case .artist: entry.id
            // An album id is "artist|albumKey", so the artist is the prefix.
            case .album: entry.id.split(separator: "|").first.map(String.init)
            case .playlist, .song: nil
            }
        }.first

        guard let artistName else { return nil }

        // Everything by them except what they just played, so the shelf is
        // "more" rather than "the thing you are already listening to".
        let recentAlbumIDs = Set(recents.recent(.album, limit: 3).map(\.id))

        let theirs = albums
            .filter { $0.artist == artistName && !recentAlbumIDs.contains($0.id) }
            .prefix(limit)

        guard theirs.count >= minimum else { return nil }

        return Shelf(
            id: "more-from-\(artistName)",
            title: "More from \(artistName)",
            reason: nil,
            albums: Array(theirs),
        )
    }

    /// Albums played once, a long time ago.
    ///
    /// Not "never played" — that is the rest of the library, and suggesting it
    /// is just browsing. Something you *did* play and have not returned to is
    /// a better bet, and it is the shelf a big library most needs.
    private static func notHeardInAWhile(
        albums: [LibraryStore.Album],
        limit: Int,
    ) -> Shelf? {
        let cutoff = Date().addingTimeInterval(-60 * 24 * 3600)

        let stale = albums
            .compactMap { album -> (LibraryStore.Album, Date)? in
                // An album is as recently played as its most recent track.
                guard let played = album.tracks.compactMap(\.lastPlayedAt).max(),
                      played < cutoff
                else { return nil }

                return (album, played)
            }
            // Oldest first: the thing most forgotten is the most interesting
            // to be reminded of.
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)

        guard stale.count >= minimum else { return nil }

        return Shelf(
            id: "not-in-a-while",
            title: "You haven't heard this in a while",
            reason: nil,
            albums: Array(stale),
        )
    }

    /// Albums you have played recently, newest first.
    ///
    /// Distinct from the recents list above it, which is per *context* and
    /// includes songs and playlists. This is albums only, and reaches further
    /// back than the handful of things you did today.
    private static func pickUpWhereYouLeftOff(
        albums: [LibraryStore.Album],
        limit: Int,
    ) -> Shelf? {
        let played = albums
            .compactMap { album -> (LibraryStore.Album, Date)? in
                guard let played = album.tracks.compactMap(\.lastPlayedAt).max() else { return nil }

                return (album, played)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)

        guard played.count >= minimum else { return nil }

        return Shelf(
            id: "recently-played-albums",
            title: "On repeat",
            reason: nil,
            albums: Array(played),
        )
    }
}
