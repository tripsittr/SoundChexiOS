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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // The API returns snake_case (release_year, parent_id); map it to Swift's
        // camelCase automatically so the models stay idiomatic.
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
            case .unreachable: "Could not reach the server."
            case .http(let status): "The server returned an error (\(status))."
            case .decoding: "The server's response was not understood."
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

    // MARK: - Library

    /// The whole catalogue.
    func library() async throws -> LibraryResponse {
        try await send("/api/v1/library", method: "GET")
    }

    // MARK: - Search

    /// Library search — titles, people, dialogue and book text, server-side.
    func search(_ term: String) async throws -> [MediaItem] {
        struct Response: Decodable { let items: [MediaItem] }

        let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let response: Response = try await send("/api/v1/search?q=\(escaped)", method: "GET")
        return response.items
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

    /// The streaming URL for one item, with the token as a query parameter so
    /// AVPlayer — which cannot set an Authorization header easily — can still
    /// authenticate. (If the API expects the header instead, the player uses a
    /// resource loader; see PlaybackURL.)
    func streamURL(itemID: Int) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/items/\(itemID)/stream"),
                                       resolvingAgainstBaseURL: false)
        if let token {
            components?.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return components?.url
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

/// Erases an `Encodable` so a heterogeneous body can be JSON-encoded.
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
