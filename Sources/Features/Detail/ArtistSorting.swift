// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// How the artist page's Songs list is ordered (S-391).
enum SongSort: String, CaseIterable, Identifiable {
    case alphabetical
    case reverseAlphabetical
    case album
    case releaseDate
    case recentlyPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: "A–Z"
        case .reverseAlphabetical: "Z–A"
        case .album: "Album"
        case .releaseDate: "Release date"
        case .recentlyPlayed: "Recently played"
        }
    }

    /// Orders tracks, keeping the comparison stable.
    ///
    /// Every case falls back to the title, so two tracks that tie — same
    /// album, same year, both never played — come back in the same order
    /// twice. Without that the list reshuffles itself on every redraw.
    func apply(_ tracks: [MediaItem]) -> [MediaItem] {
        switch self {
        case .alphabetical:
            tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .reverseAlphabetical:
            tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }

        case .album:
            // Album, then disc and track within it — the order the record was
            // meant to be heard in.
            tracks.sorted {
                let a = ($0.meta?.album ?? "", $0.meta?.discNumber ?? 0, $0.meta?.trackNumber ?? 0, $0.title)
                let b = ($1.meta?.album ?? "", $1.meta?.discNumber ?? 0, $1.meta?.trackNumber ?? 0, $1.title)

                return a < b
            }

        case .releaseDate:
            // Newest first. A track with no year sorts last rather than as
            // year zero, which would put unknowns at the top of every list.
            tracks.sorted {
                let a = $0.meta?.releaseYear ?? Int.min
                let b = $1.meta?.releaseYear ?? Int.min

                return a == b
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : a > b
            }

        case .recentlyPlayed:
            // Never played sorts last, for the same reason.
            tracks.sorted {
                let a = $0.lastPlayedAt ?? .distantPast
                let b = $1.lastPlayedAt ?? .distantPast

                return a == b
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : a > b
            }
        }
    }
}

/// How the artist page's Albums grid is ordered (S-391).
enum AlbumSort: String, CaseIterable, Identifiable {
    case alphabetical
    case reverseAlphabetical
    case releaseDate
    case recentlyPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: "A–Z"
        case .reverseAlphabetical: "Z–A"
        case .releaseDate: "Release date"
        case .recentlyPlayed: "Recently played"
        }
    }

    func apply(_ albums: [LibraryStore.Album]) -> [LibraryStore.Album] {
        switch self {
        case .alphabetical:
            albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .reverseAlphabetical:
            albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }

        case .releaseDate:
            albums.sorted {
                let a = Self.year(of: $0)
                let b = Self.year(of: $1)

                return a == b
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : a > b
            }

        case .recentlyPlayed:
            // An album is as recent as its most recently played track: half a
            // record played yesterday is a record played yesterday.
            albums.sorted {
                let a = Self.lastPlayed(of: $0)
                let b = Self.lastPlayed(of: $1)

                return a == b
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : a > b
            }
        }
    }

    /// The album's year: the earliest its tracks claim, so a reissued bonus
    /// track does not date the whole record to this year.
    private static func year(of album: LibraryStore.Album) -> Int {
        album.tracks.compactMap { $0.meta?.releaseYear }.min() ?? Int.min
    }

    private static func lastPlayed(of album: LibraryStore.Album) -> Date {
        album.tracks.compactMap(\.lastPlayedAt).max() ?? .distantPast
    }
}
