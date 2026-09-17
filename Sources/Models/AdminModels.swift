import Foundation

/// A JSON value that is a string, an int, or null — enough to carry the mixed
/// metadata fields (artist text, release_year int) an item edit sends back.
enum AnyCodableValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .null: ""
        }
    }
}

/// An item's editable admin detail.
struct AdminItem: Decodable, Sendable {
    let id: Int
    let type: MediaType
    let title: String
    let artwork: URL?
    let userRating: Double?
    let notes: String?
    let meta: [String: AnyCodableValue]
}

/// A profile as the admin API returns it.
struct AdminProfile: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let color: String?
    let initial: String?
    let avatarURL: URL?
    let isOwner: Bool
    let isKids: Bool
    let requiresPin: Bool
    let maxRating: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color, initial, avatarUrl, isOwner, isKids, requiresPin, maxRating
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        initial = try c.decodeIfPresent(String.self, forKey: .initial)
        avatarURL = try c.decodeIfPresent(URL.self, forKey: .avatarUrl)
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        isKids = try c.decodeIfPresent(Bool.self, forKey: .isKids) ?? false
        requiresPin = try c.decodeIfPresent(Bool.self, forKey: .requiresPin) ?? false
        maxRating = try c.decodeIfPresent(String.self, forKey: .maxRating)
    }
}

struct AdminProfilesResponse: Decodable, Sendable {
    let profiles: [AdminProfile]
    let ratings: [String]
}
