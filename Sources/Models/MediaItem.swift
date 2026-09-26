// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// One thing in the library: a song, a film, a show (or its episode), a book.
///
/// The shape mirrors what /api/v1/library returns. Decoding is deliberately
/// defensive: explicit snake_case keys (not the decoder's key strategy, which
/// mangled `parent_id`), every field tolerant of being absent, and a bad artwork
/// string treated as no artwork rather than a decode failure that would take the
/// whole catalogue down — which is exactly the "server couldn't load" symptom.
struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let type: MediaType
    let title: String
    let subtitle: String?
    let parentID: Int?
    let playable: Bool
    /// When the current profile last played this, for a "recently played"
    /// sort. Nil for something never played (S-391).
    let lastPlayedAt: Date?
    /// Absolute artwork URL the server resolved, or nil. Public — no token.
    let artwork: URL?
    let meta: Meta?

    // The decoder applies .convertFromSnakeCase first, so the keys these match
    // against are already camelCase: parent_id arrives as "parentId".
    enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, playable, artwork, meta, lastPlayedAt
        case parentID = "parentId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        type = (try? c.decode(MediaType.self, forKey: .type)) ?? .unknown
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled"
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        parentID = try? c.decodeIfPresent(Int.self, forKey: .parentID)
        playable = (try? c.decodeIfPresent(Bool.self, forKey: .playable)) ?? false
        // A server that predates this sends nothing; sorting simply treats
        // those as never played rather than failing the whole item.
        lastPlayedAt = ((try? c.decodeIfPresent(String.self, forKey: .lastPlayedAt)) ?? nil)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        // A malformed or relative artwork string is treated as no artwork.
        artwork = (try? c.decodeIfPresent(String.self, forKey: .artwork)).flatMap { $0.flatMap(URL.init(string:)) }
        meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
    }

    /// A direct initialiser, for building an item from stored/offline data
    /// rather than a server response (a custom decoder suppresses the synthesised
    /// memberwise one).
    init(id: Int, type: MediaType, title: String, subtitle: String?,
         parentID: Int?, playable: Bool, artwork: URL?, meta: Meta?,
         lastPlayedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.parentID = parentID
        self.playable = playable
        self.artwork = artwork
        self.meta = meta
        self.lastPlayedAt = lastPlayedAt
    }

    /// For the on-disk library cache. Written and read by us, so a plain encode
    /// is fine (the decoder is lenient for the server's shape; this round-trips
    /// our own).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(playable, forKey: .playable)
        try c.encodeIfPresent(artwork?.absoluteString, forKey: .artwork)
        try c.encodeIfPresent(meta, forKey: .meta)
        // As an ISO string, matching what the server sends — so a cached item
        // decodes the same way a fetched one does and the sort survives a
        // relaunch.
        try c.encodeIfPresent(
            lastPlayedAt.map { ISO8601DateFormatter().string(from: $0) },
            forKey: .lastPlayedAt,
        )
    }

    struct Meta: Codable, Hashable, Sendable {
        let artist: String?
        /// The headline artist for grouping — a track credited "Artist, Someone"
        /// belongs under "Artist". The server derives it; nil falls back to
        /// `artist` via `groupingArtist`.
        let primaryArtist: String?
        let album: String?
        /// The canonical album key for grouping — edition/punctuation variants of
        /// one album share it. The server derives it; nil falls back to `album`
        /// via `groupingAlbum`.
        let albumKey: String?
        let author: String?
        let director: String?
        let episodeTitle: String?
        let trackNumber: Int?
        let discNumber: Int?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let releaseYear: Int?
        let durationMs: Int?

        // The wider film and show detail the server now sends (S-412). All
        // optional: a library item that was never enriched has none of it,
        // and a detail page shows what it has rather than blank rows.
        let tagline: String?
        let studio: String?
        let language: String?
        let country: String?
        let imdbRating: Double?
        let rtScore: Int?
        let mpaaRating: String?
        let runtimeMinutes: Int?
        let creator: String?
        let network: String?
        let firstAirYear: Int?
        let lastAirYear: Int?
        let seasonCount: Int?
        let episodeCount: Int?
        let status: String?
        let contentRating: String?

        /// The artist to group and browse by: the primary when known, else the
        /// full credit. Everything that lists artists should use this, not
        /// `artist`, or featured tracks split into their own artists.
        var groupingArtist: String? {
            (primaryArtist?.isEmpty == false ? primaryArtist : nil) ?? artist
        }

        /// The album key to group by: the server's canonical key when known, else
        /// the album title. Everything that lists albums should group on this, not
        /// `album`, or edition variants split into their own albums.
        var groupingAlbum: String? {
            (albumKey?.isEmpty == false ? albumKey : nil) ?? album
        }

        // Names already transformed by .convertFromSnakeCase, so the raw values
        // here are camelCase and equal to the property names — the enum is kept
        // explicit only so the mapping is visible and cannot silently drift.
        enum CodingKeys: String, CodingKey {
            case artist, primaryArtist, album, albumKey, author, director
            case episodeTitle, trackNumber, discNumber
            case seasonNumber, episodeNumber, releaseYear, durationMs
            // Film and show detail (S-412). Snake_case on the wire; the
            // decoder converts, so these match the server's keys.
            case tagline, studio, language, country, imdbRating, rtScore
            case mpaaRating, runtimeMinutes
            case creator, network, firstAirYear, lastAirYear
            case seasonCount, episodeCount, status, contentRating
        }

        /// Direct initialiser for building from stored data (offline entries).
        init(artist: String? = nil, primaryArtist: String? = nil, album: String? = nil, albumKey: String? = nil,
             author: String? = nil,
             director: String? = nil, episodeTitle: String? = nil,
             trackNumber: Int? = nil, discNumber: Int? = nil,
             seasonNumber: Int? = nil, episodeNumber: Int? = nil,
             releaseYear: Int? = nil, durationMs: Int? = nil,
             tagline: String? = nil, studio: String? = nil, language: String? = nil,
             country: String? = nil, imdbRating: Double? = nil, rtScore: Int? = nil,
             mpaaRating: String? = nil, runtimeMinutes: Int? = nil,
             creator: String? = nil, network: String? = nil,
             firstAirYear: Int? = nil, lastAirYear: Int? = nil,
             seasonCount: Int? = nil, episodeCount: Int? = nil,
             status: String? = nil, contentRating: String? = nil) {
            self.artist = artist; self.primaryArtist = primaryArtist; self.album = album; self.albumKey = albumKey
            self.author = author
            self.director = director; self.episodeTitle = episodeTitle
            self.trackNumber = trackNumber; self.discNumber = discNumber
            self.seasonNumber = seasonNumber; self.episodeNumber = episodeNumber
            self.releaseYear = releaseYear; self.durationMs = durationMs
            self.tagline = tagline; self.studio = studio; self.language = language
            self.country = country; self.imdbRating = imdbRating; self.rtScore = rtScore
            self.mpaaRating = mpaaRating; self.runtimeMinutes = runtimeMinutes
            self.creator = creator; self.network = network
            self.firstAirYear = firstAirYear; self.lastAirYear = lastAirYear
            self.seasonCount = seasonCount; self.episodeCount = episodeCount
            self.status = status; self.contentRating = contentRating
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            artist = try? c.decodeIfPresent(String.self, forKey: .artist)
            primaryArtist = try? c.decodeIfPresent(String.self, forKey: .primaryArtist)
            album = try? c.decodeIfPresent(String.self, forKey: .album)
            albumKey = try? c.decodeIfPresent(String.self, forKey: .albumKey)
            author = try? c.decodeIfPresent(String.self, forKey: .author)
            director = try? c.decodeIfPresent(String.self, forKey: .director)
            episodeTitle = try? c.decodeIfPresent(String.self, forKey: .episodeTitle)
            trackNumber = try? c.decodeIfPresent(Int.self, forKey: .trackNumber)
            discNumber = try? c.decodeIfPresent(Int.self, forKey: .discNumber)
            seasonNumber = try? c.decodeIfPresent(Int.self, forKey: .seasonNumber)
            episodeNumber = try? c.decodeIfPresent(Int.self, forKey: .episodeNumber)
            releaseYear = try? c.decodeIfPresent(Int.self, forKey: .releaseYear)
            durationMs = try? c.decodeIfPresent(Int.self, forKey: .durationMs)
            tagline = try? c.decodeIfPresent(String.self, forKey: .tagline)
            studio = try? c.decodeIfPresent(String.self, forKey: .studio)
            language = try? c.decodeIfPresent(String.self, forKey: .language)
            country = try? c.decodeIfPresent(String.self, forKey: .country)
            imdbRating = try? c.decodeIfPresent(Double.self, forKey: .imdbRating)
            rtScore = try? c.decodeIfPresent(Int.self, forKey: .rtScore)
            mpaaRating = try? c.decodeIfPresent(String.self, forKey: .mpaaRating)
            runtimeMinutes = try? c.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
            creator = try? c.decodeIfPresent(String.self, forKey: .creator)
            network = try? c.decodeIfPresent(String.self, forKey: .network)
            firstAirYear = try? c.decodeIfPresent(Int.self, forKey: .firstAirYear)
            lastAirYear = try? c.decodeIfPresent(Int.self, forKey: .lastAirYear)
            seasonCount = try? c.decodeIfPresent(Int.self, forKey: .seasonCount)
            episodeCount = try? c.decodeIfPresent(Int.self, forKey: .episodeCount)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            contentRating = try? c.decodeIfPresent(String.self, forKey: .contentRating)
        }
    }
}

enum MediaType: String, Codable, CaseIterable, Sendable {
    case music, movie, show, book
    /// The catch-all for a value the server adds later that this build predates.
    case unknown

    /// Whether this is video, which is the type big enough to be worth asking
    /// how long to keep (S-404). A film is 2–10GB; a song is 5MB.
    var isVideo: Bool { self == .movie || self == .show }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaType(rawValue: raw) ?? .unknown
    }
}

/// The catalogue as the API returns it.
struct LibraryResponse: Decodable, Sendable {
    let items: [MediaItem]
    let syncedAt: String?
    // synced_at arrives as syncedAt after the key transform — synthesized keys
    // match, so no explicit map is needed.
}

/// What `/library/delta` returns: the items that changed since `since`, and the
/// ids the device should drop (deleted, or no longer permitted).
struct LibraryDeltaResponse: Decodable, Sendable {
    let items: [MediaItem]
    let removedIds: [Int]
    let syncedAt: String?
    let count: Int?
}
