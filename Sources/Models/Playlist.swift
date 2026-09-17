import Foundation

/// A playlist (a Collection on the server), account-scoped and shared across the
/// account's profiles. The list form carries a count; the detail form carries
/// the tracks.
struct Playlist: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let count: Int?
}

/// A playlist with its tracks, from the detail endpoint.
struct PlaylistDetail: Decodable, Sendable {
    let id: Int
    let name: String
    let items: [MediaItem]
}
