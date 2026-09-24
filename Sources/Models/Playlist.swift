// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// A playlist (a Collection on the server), account-scoped and shared across the
/// account's profiles. The list form carries a count and cover; the detail form
/// carries the tracks and total duration.
struct Playlist: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let count: Int?
    /// The playlist's own cover, or nil — then the UI draws a mosaic of the
    /// tracks' covers.
    let artworkURL: URL?
    /// Up to four track covers for that mosaic. The list endpoint carries no
    /// tracks, so without these a playlist with no cover of its own had
    /// nothing to draw and fell back to a note glyph (S-371).
    let mosaic: [URL]

    enum CodingKeys: String, CodingKey {
        case id, name, description, count, mosaic
        case artworkURL = "artworkUrl" // artwork_url → artworkUrl after the key transform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Playlist"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        artworkURL = (try? c.decodeIfPresent(String.self, forKey: .artworkURL))
            .flatMap { $0.flatMap(URL.init(string:)) }
        // A server that has not been updated sends no mosaic at all, so this
        // must degrade to empty rather than fail the whole playlist.
        mosaic = ((try? c.decodeIfPresent([String].self, forKey: .mosaic)) ?? [])?
            .compactMap(URL.init(string:)) ?? []
    }
}

/// A playlist with its tracks, from the detail endpoint.
struct PlaylistDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let artworkURL: URL?
    let count: Int?
    let durationMs: Int?
    let items: [MediaItem]

    enum CodingKeys: String, CodingKey {
        case id, name, description, count, items
        case artworkURL = "artworkUrl"
        case durationMs // duration_ms → durationMs after the key transform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Playlist"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        artworkURL = (try? c.decodeIfPresent(String.self, forKey: .artworkURL))
            .flatMap { $0.flatMap(URL.init(string:)) }
        count = try? c.decodeIfPresent(Int.self, forKey: .count)
        durationMs = try? c.decodeIfPresent(Int.self, forKey: .durationMs)
        items = (try? c.decodeIfPresent([MediaItem].self, forKey: .items)) ?? []
    }
}
