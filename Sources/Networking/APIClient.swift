import Foundation

/// Talks to the SoundChex server's JSON API.
///
/// One client per signed-in server, carrying the bearer token on every request.
/// Deliberately thin: it builds requests, decodes JSON, and surfaces failures as
/// typed errors — the features above decide what to do with them. The exact
/// endpoint paths are the ones the web app already uses (/api/v1/*); any that
/// the API audit shows are missing get built on the server side.
struct APIClient {
    let baseURL: URL
    let token: String?

    // snake_case JSON → camelCase Swift. Models that need a name the strategy
    // wouldn't produce (e.g. parentID from parent_id) map that one key explicitly
    // to the *transformed* name; see MediaItem.CodingKeys.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Swift camelCase (profileId, deviceName) → the API's snake_case
        // (profile_id, device_name).
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    enum APIError: Error, LocalizedError {
        case badURL
        case unreachable(underlying: Error)
        case http(status: Int)
        case decoding(underlying: Error)
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .badURL: "That server address is not valid."
            case .unreachable(let e): "Could not reach the server. (\(e.localizedDescription))"
            case .http(let status): "The server returned an error (\(status))."
            case .decoding(let e): "The server's response was not understood. (\(decodingHint(e)))"
            case .unauthorized: "Your email or password was not accepted."
            }
        }
    }

    // MARK: - Auth

    /// The profiles on an account, so the user can pick which one to sign in as.
    ///
    /// A SoundChex token is bound to one profile, and the login endpoint requires
    /// a `profile_id` the app cannot know before authenticating. So sign-in is two
    /// steps: verify the credentials and list the profiles, then mint a token for
    /// the chosen one. (Endpoint to be added on the server: POST /api/v1/profiles.)
    func profiles(email: String, password: String) async throws -> [Profile] {
        struct Body: Encodable { let email: String; let password: String }
        struct Response: Decodable { let profiles: [Profile] }

        let response: Response = try await send(
            "/api/v1/profiles",
            method: "POST",
            body: Body(email: email, password: password)
        )

        return response.profiles
    }

    /// Exchanges credentials + a chosen profile for a bearer token.
    ///
    /// `POST /api/v1/tokens` requires the profile id and a device name, and a PIN
    /// when the profile is locked. Returns `{ "token": ..., "profile": {...} }`.
    func login(email: String, password: String, profileID: Int,
               pin: String?, deviceName: String) async throws -> String {
        struct Body: Encodable {
            let email: String
            let password: String
            let profileId: Int
            let pin: String?
            let deviceName: String
        }
        struct Response: Decodable { let token: String }

        let response: Response = try await send(
            "/api/v1/tokens",
            method: "POST",
            body: Body(email: email, password: password, profileId: profileID,
                       pin: pin, deviceName: deviceName)
        )

        return response.token
    }

    /// Revokes the current token on the server.
    func logout() async throws {
        _ = try await sendRaw("/api/v1/tokens/current", method: "DELETE")
    }

    /// The account's profiles, for a *signed-in* device — no password needed,
    /// because the token proves the account. Used by the in-app profile switcher.
    func myProfiles() async throws -> [Profile] {
        struct Response: Decodable { let profiles: [Profile] }
        let response: Response = try await send("/api/v1/profiles/mine", method: "GET")
        return response.profiles
    }

    /// Switches to another profile on the same account without re-authenticating.
    /// Returns a fresh token bound to the chosen profile; the old one is revoked.
    func switchProfile(profileID: Int, pin: String?, deviceName: String) async throws -> String {
        struct Body: Encodable {
            let profileId: Int
            let pin: String?
            let deviceName: String
        }
        struct Response: Decodable { let token: String }
        let response: Response = try await send(
            "/api/v1/profiles/switch", method: "POST",
            body: Body(profileId: profileID, pin: pin, deviceName: deviceName)
        )
        return response.token
    }

    // MARK: - Library

    /// The whole catalogue.
    func library() async throws -> LibraryResponse {
        try await send("/api/v1/library", method: "GET")
    }

    /// What changed since a previous sync. `since` is the server's own
    /// `synced_at` from the last fetch (never a device clock), and `knownIDs` is
    /// everything the device holds, so the server can name what to drop —
    /// deletions and a tightened rating cap alike.
    func libraryDelta(since: String, knownIDs: [Int]) async throws -> LibraryDeltaResponse {
        struct Body: Encodable {
            let since: String
            let knownIds: [Int]
        }
        return try await send(
            "/api/v1/library/delta", method: "POST",
            body: Body(since: since, knownIds: knownIDs)
        )
    }

    // MARK: - Search

    /// Library search — titles, people, dialogue and book text, server-side.
    func search(_ term: String) async throws -> [MediaItem] {
        struct Response: Decodable { let items: [MediaItem] }

        let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let response: Response = try await send("/api/v1/search?q=\(escaped)", method: "GET")
        return response.items
    }

    // MARK: - Identity / admin

    /// Who this token belongs to, and whether the profile may administer.
    func me() async throws -> Identity {
        try await send("/api/v1/me", method: "GET")
    }

    /// Admin dashboard figures. 403 if the profile is not an admin.
    func adminStats() async throws -> AdminStats {
        try await send("/api/v1/admin/stats", method: "GET")
    }

    /// One item's editable admin detail.
    func adminItem(_ id: Int) async throws -> AdminItem {
        try await send("/api/v1/admin/items/\(id)", method: "GET")
    }

    /// Saves an item's edited fields. `meta` carries the type's fields.
    func updateAdminItem(_ id: Int, title: String, userRating: Double?,
                         notes: String?, meta: [String: AnyCodableValue]) async throws -> AdminItem {
        struct Body: Encodable {
            let title: String
            let userRating: Double?
            let notes: String?
            let meta: [String: AnyCodableValue]
        }
        return try await send("/api/v1/admin/items/\(id)", method: "PATCH",
                              body: Body(title: title, userRating: userRating, notes: notes, meta: meta))
    }

    /// The account's profiles for management, plus the rating ladder.
    func adminProfiles() async throws -> AdminProfilesResponse {
        try await send("/api/v1/admin/profiles", method: "GET")
    }

    /// Creates a profile.
    func createProfile(name: String, color: String?, isKids: Bool,
                       maxRating: String?, pin: String?) async throws -> AdminProfile {
        struct Body: Encodable {
            let name: String; let color: String?; let isKids: Bool
            let maxRating: String?; let pin: String?
        }
        return try await send("/api/v1/admin/profiles", method: "POST",
                              body: Body(name: name, color: color, isKids: isKids,
                                         maxRating: maxRating, pin: pin))
    }

    /// Updates a profile.
    func updateProfile(_ id: Int, name: String?, color: String?, isKids: Bool?,
                       maxRating: String?, pin: String?) async throws -> AdminProfile {
        struct Body: Encodable {
            let name: String?; let color: String?; let isKids: Bool?
            let maxRating: String?; let pin: String?
        }
        return try await send("/api/v1/admin/profiles/\(id)", method: "PATCH",
                              body: Body(name: name, color: color, isKids: isKids,
                                         maxRating: maxRating, pin: pin))
    }

    /// Deletes a profile.
    func deleteProfile(_ id: Int) async throws {
        _ = try await sendRaw("/api/v1/admin/profiles/\(id)", method: "DELETE")
    }

    /// Queues a library scan to pick up newly-added files.
    func triggerScan() async throws {
        _ = try await sendRaw("/api/v1/admin/scan", method: "POST")
    }

    // MARK: - Playlists

    /// The account's playlists, for the picker.
    func playlists() async throws -> [Playlist] {
        struct Response: Decodable { let playlists: [Playlist] }
        let response: Response = try await send("/api/v1/playlists", method: "GET")
        return response.playlists
    }

    /// One playlist and its tracks.
    func playlist(_ id: Int) async throws -> PlaylistDetail {
        try await send("/api/v1/playlists/\(id)", method: "GET")
    }

    /// Creates a playlist, returning it.
    func createPlaylist(name: String) async throws -> Playlist {
        struct Body: Encodable { let name: String }
        return try await send("/api/v1/playlists", method: "POST", body: Body(name: name))
    }

    /// Adds an item to a playlist.
    func addToPlaylist(_ playlistID: Int, itemID: Int) async throws {
        struct Body: Encodable { let itemId: Int }
        _ = try await sendRaw("/api/v1/playlists/\(playlistID)/items", method: "POST",
                              body: Body(itemId: itemID))
    }

    /// Removes an item from a playlist.
    func removeFromPlaylist(_ playlistID: Int, itemID: Int) async throws {
        _ = try await sendRaw("/api/v1/playlists/\(playlistID)/items/\(itemID)", method: "DELETE")
    }

    /// Deletes a playlist (the tracks are untouched).
    func deletePlaylist(_ id: Int) async throws {
        _ = try await sendRaw("/api/v1/playlists/\(id)", method: "DELETE")
    }

    // MARK: - Lyrics

    /// The lyrics for a track, or nil when the server has none. The server
    /// fetches and caches them from a lyric provider; the app just reads them.
    func lyrics(itemID: Int) async throws -> String? {
        struct Response: Decodable { let lyrics: String? }
        // A 404 (no lyrics) is not an error worth surfacing — return nil.
        do {
            let response: Response = try await send("/api/v1/items/\(itemID)/lyrics", method: "GET")
            return response.lyrics
        } catch APIError.http(404) {
            return nil
        }
    }

    // MARK: - Progress

    struct Progress: Decodable, Sendable { let position: Int; let completed: Bool }

    /// The resume position for an item, so a track picks up where it stopped.
    func progress(itemID: Int) async throws -> Progress {
        try await send("/api/v1/items/\(itemID)/progress", method: "GET")
    }

    /// Reports a playback position back to the server.
    func saveProgress(itemID: Int, position: Int, duration: Int) async throws {
        struct Body: Encodable { let position: Int; let duration: Int }
        _ = try await sendRaw("/api/v1/items/\(itemID)/progress", method: "POST",
                              body: Body(position: position, duration: duration))
    }

    // MARK: - URLs (for streaming and artwork, used directly by AVPlayer / AsyncImage)

    /// The streaming URL for one item. Authentication is the bearer token in the
    /// Authorization header, which the player attaches to the AVURLAsset (a query
    /// token is ignored by Sanctum), so no token rides on the URL.
    func streamURL(itemID: Int) -> URL? {
        baseURL.appendingPathComponent("/api/v1/items/\(itemID)/stream")
    }

    /// The artwork URL for one item.
    func artworkURL(itemID: Int) -> URL? {
        baseURL.appendingPathComponent("/api/v1/items/\(itemID)/artwork")
    }

    // MARK: - Transport

    private func send<Response: Decodable>(
        _ path: String,
        method: String,
        body: (any Encodable)? = nil
    ) async throws -> Response {
        let data = try await sendRaw(path, method: method, body: body)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    @discardableResult
    private func sendRaw(
        _ path: String,
        method: String,
        body: (any Encodable)? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.unreachable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1)
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode)
        }

        return data
    }
}

/// A short, human-readable reason a decode failed — which key or type, so a
/// "response not understood" error names the actual mismatch instead of hiding it.
private func decodingHint(_ error: Error) -> String {
    guard let decoding = error as? DecodingError else {
        return String(describing: error).prefix(80).description
    }

    switch decoding {
    case .keyNotFound(let key, _):
        return "missing '\(key.stringValue)'"
    case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx):
        let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
        return "type mismatch at '\(path)'"
    case .dataCorrupted(let ctx):
        return "corrupted: \(ctx.debugDescription.prefix(60))"
    @unknown default:
        return "unknown decode error"
    }
}

/// Erases an `Encodable` so a heterogeneous body can be JSON-encoded.
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
