import Foundation

/// One thing in the library: a song, a film, a show (or its episode), a book.
///
/// The shape mirrors what /api/v1/library returns, which the web mirror stored
/// verbatim. Optional fields are genuinely optional across types — a song has an
/// artist, a film a director, a book an author — so they are modelled as such
/// rather than forced into one flat schema.
struct MediaItem: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let type: MediaType
    let title: String
    let subtitle: String?
    let parentID: Int?
    let playable: Bool
    /// Absolute artwork URL the server resolved (local /storage or an external
    /// source), or nil. Public — loadable with no token.
    let artwork: URL?
    let meta: Meta?

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
    }
}

enum MediaType: String, Decodable, CaseIterable, Sendable {
    case music
    case movie
    case show
    case book

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
}
