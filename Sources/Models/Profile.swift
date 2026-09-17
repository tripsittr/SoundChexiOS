import Foundation

/// A viewing profile on an account.
///
/// One account can hold several profiles (a household), each with its own content
/// rating cap and optional PIN. A token is bound to exactly one, so signing in
/// means choosing which. `requiresPin` tells the sign-in flow whether to ask.
struct Profile: Identifiable, Decodable, Hashable, Sendable {
    let id: Int
    let name: String
    let isOwner: Bool
    let requiresPin: Bool
    let isKids: Bool

    // The server may omit the newer flags on an older build; default them so an
    // old server still lets you sign in.
    enum CodingKeys: String, CodingKey {
        case id, name, isOwner, requiresPin, isKids
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isOwner = try c.decodeIfPresent(Bool.self, forKey: .isOwner) ?? false
        requiresPin = try c.decodeIfPresent(Bool.self, forKey: .requiresPin) ?? false
        isKids = try c.decodeIfPresent(Bool.self, forKey: .isKids) ?? false
    }
}
