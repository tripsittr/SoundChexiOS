import Foundation

/// One thing in the library: a song, a film, a show (or its episode), a book.
///
/// The shape mirrors what /api/v1/library returns. Decoding is deliberately
/// defensive: explicit snake_case keys (not the decoder's key strategy, which
/// mangled `parent_id`), every field tolerant of being absent, and a bad artwork
/// string treated as no artwork rather than a decode failure that would take the
/// whole catalogue down — which is exactly the "server couldn't load" symptom.
struct MediaItem: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let type: MediaType
    let title: String
    let subtitle: String?
    let parentID: Int?
    let playable: Bool
    /// Absolute artwork URL the server resolved, or nil. Public — no token.
    let artwork: URL?
    let meta: Meta?

    // The decoder applies .convertFromSnakeCase first, so the keys these match
    // against are already camelCase: parent_id arrives as "parentId".
    enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, playable, artwork, meta
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
        // A malformed or relative artwork string is treated as no artwork.
        artwork = (try? c.decodeIfPresent(String.self, forKey: .artwork)).flatMap { $0.flatMap(URL.init(string:)) }
        meta = try? c.decodeIfPresent(Meta.self, forKey: .meta)
    }

    struct Meta: Decodable, Hashable, Sendable {
        let artist: String?
        let album: String?
        let author: String?
        let director: String?
        let episodeTitle: String?
        let trackNumber: Int?
        let discNumber: Int?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let releaseYear: Int?
        let durationMs: Int?

        // Names already transformed by .convertFromSnakeCase, so the raw values
        // here are camelCase and equal to the property names — the enum is kept
        // explicit only so the mapping is visible and cannot silently drift.
        enum CodingKeys: String, CodingKey {
            case artist, album, author, director
            case episodeTitle, trackNumber, discNumber
            case seasonNumber, episodeNumber, releaseYear, durationMs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            artist = try? c.decodeIfPresent(String.self, forKey: .artist)
            album = try? c.decodeIfPresent(String.self, forKey: .album)
            author = try? c.decodeIfPresent(String.self, forKey: .author)
            director = try? c.decodeIfPresent(String.self, forKey: .director)
            episodeTitle = try? c.decodeIfPresent(String.self, forKey: .episodeTitle)
            trackNumber = try? c.decodeIfPresent(Int.self, forKey: .trackNumber)
            discNumber = try? c.decodeIfPresent(Int.self, forKey: .discNumber)
            seasonNumber = try? c.decodeIfPresent(Int.self, forKey: .seasonNumber)
            episodeNumber = try? c.decodeIfPresent(Int.self, forKey: .episodeNumber)
            releaseYear = try? c.decodeIfPresent(Int.self, forKey: .releaseYear)
            durationMs = try? c.decodeIfPresent(Int.self, forKey: .durationMs)
        }
    }
}

enum MediaType: String, Decodable, CaseIterable, Sendable {
    case music, movie, show, book
    /// The catch-all for a value the server adds later that this build predates.
    case unknown

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
