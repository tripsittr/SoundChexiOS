// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

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
        /// The playlist already holds this track (S-373).
        case alreadyInPlaylist

        var errorDescription: String? {
            switch self {
            case .badURL: "That server address is not valid."
            case .unreachable(let e): "Could not reach the server. (\(e.localizedDescription))"
            case .http(let status): "The server returned an error (\(status))."
            case .decoding(let e): "The server's response was not understood. (\(decodingHint(e)))"
            case .unauthorized: "Your email or password was not accepted."
            case .alreadyInPlaylist: "That song is already in this playlist."
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

    /// A shuffled queue of the music library, built server-side (S-289).
    ///
    /// `smart` weights the draw by what this profile actually plays. Built on
    /// the server because weighting it here would mean the phone holding the
    /// whole library and the whole play history.
    func shuffleLibrary(smart: Bool, limit: Int = 200) async throws -> [MediaItem] {
        struct Response: Decodable { let items: [MediaItem] }

        let response: Response = try await send(
            "/api/v1/library/shuffle?smart=\(smart ? 1 : 0)&limit=\(limit)",
            method: "GET",
        )

        return response.items
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
    func createPlaylist(name: String, description: String? = nil) async throws -> Playlist {
        struct Body: Encodable { let name: String; let description: String? }
        return try await send("/api/v1/playlists", method: "POST",
                              body: Body(name: name, description: description))
    }

    /// Renames a playlist and/or edits its description, returning the updated one.
    func updatePlaylist(_ id: Int, name: String?, description: String?) async throws -> Playlist {
        struct Body: Encodable { let name: String?; let description: String? }
        return try await send("/api/v1/playlists/\(id)", method: "PATCH",
                              body: Body(name: name, description: description))
    }

    /// Persists a drag-reorder: the full ordered list of the playlist's item ids.
    func reorderPlaylist(_ id: Int, order: [Int]) async throws {
        struct Body: Encodable { let order: [Int] }
        _ = try await sendRaw("/api/v1/playlists/\(id)/order", method: "PUT", body: Body(order: order))
    }

    /// Uploads a cover image (JPEG data) for a playlist, returning its new URL.
    func uploadPlaylistCover(_ id: Int, jpeg: Data) async throws -> URL? {
        struct Response: Decodable { let artworkURL: URL?
            enum CodingKeys: String, CodingKey { case artworkURL = "artworkUrl" } }
        let data = try await sendMultipart(
            "/api/v1/playlists/\(id)/cover",
            fileField: "cover", filename: "cover.jpg", mimeType: "image/jpeg", fileData: jpeg
        )
        return (try? decoder.decode(Response.self, from: data))?.artworkURL
    }

    /// Adds an item to a playlist.
    ///
    /// A playlist cannot hold the same track twice, so a track already on it
    /// throws `alreadyInPlaylist` rather than silently moving it to the end —
    /// which is what the server used to do. Pass `moveToEnd` to ask for that
    /// deliberately (S-373).
    func addToPlaylist(_ playlistID: Int, itemID: Int, moveToEnd: Bool = false) async throws {
        struct Body: Encodable { let itemId: Int; let moveToEnd: Bool }

        do {
            _ = try await sendRaw("/api/v1/playlists/\(playlistID)/items", method: "POST",
                                  body: Body(itemId: itemID, moveToEnd: moveToEnd))
        } catch APIError.http(status: 409) {
            throw APIError.alreadyInPlaylist
        }
    }

    /// Removes an item from a playlist.
    func removeFromPlaylist(_ playlistID: Int, itemID: Int) async throws {
        _ = try await sendRaw("/api/v1/playlists/\(playlistID)/items/\(itemID)", method: "DELETE")
    }

    /// Deletes a playlist (the tracks are untouched).
    func deletePlaylist(_ id: Int) async throws {
        _ = try await sendRaw("/api/v1/playlists/\(id)", method: "DELETE")
    }

    // MARK: - Playlist porting (S-313)

    /// The result of porting a playlist: how many tracks matched the library, the
    /// ones that didn't, and the playlist it created.
    struct PlaylistImport: Decodable, Sendable, Identifiable {
        struct Unmatched: Decodable, Sendable, Hashable, Identifiable {
            let title: String?
            let artist: String?
            let album: String?
            let sourceLabel: String?
            var id: String { [title, artist, album, sourceLabel].compactMap { $0 }.joined(separator: "|") }

            enum CodingKeys: String, CodingKey {
                case title, artist, album, sourceLabel = "source_label"
            }
        }

        let id: Int
        let name: String?
        let status: String
        let total: Int
        let matched: Int
        let unmatched: [Unmatched]
        let playlistID: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, status, total, matched, unmatched
            case playlistID = "playlist_id"
        }
    }

    /// Imports a playlist file (M3U/CSV/XSPF), returning the port's result.
    func importPlaylistFile(_ data: Data, filename: String, name: String?) async throws -> PlaylistImport {
        let responseData = try await sendMultipart(
            "/api/v1/playlists/imports",
            fileField: "file", filename: filename, mimeType: "application/octet-stream", fileData: data,
            fields: name.map { ["name": $0] } ?? [:]
        )
        return try decoder.decode(PlaylistImport.self, from: responseData)
    }

    /// The current state of an import — for polling a queued one.
    func playlistImport(_ id: Int) async throws -> PlaylistImport {
        try await send("/api/v1/playlists/imports/\(id)", method: "GET")
    }

    /// Resolve an unmatched track by attaching a chosen library item.
    func resolvePlaylistImport(_ id: Int, index: Int, itemID: Int) async throws -> PlaylistImport {
        struct Body: Encodable { let index: Int; let itemId: Int }
        let data = try await sendRaw("/api/v1/playlists/imports/\(id)/resolve", method: "POST",
                                     body: Body(index: index, itemId: itemID))
        return try decoder.decode(PlaylistImport.self, from: data)
    }

    // MARK: - Lyrics

    /// A track's lyrics: the plain words, and — when available — time-synced LRC
    /// text for the scroll-highlight. Either may be nil. The server fetches and
    /// caches these; the app just reads them.
    struct Lyrics: Decodable, Sendable {
        let plain: String?
        let synced: String?

        enum CodingKeys: String, CodingKey {
            case plain = "lyrics"
            case synced
        }
    }

    /// The lyrics for a track, or nil when the server has none.
    func lyrics(itemID: Int) async throws -> Lyrics? {
        // A 404 (no lyrics) is not an error worth surfacing — return nil.
        do {
            let lyrics: Lyrics = try await send("/api/v1/items/\(itemID)/lyrics", method: "GET")
            if lyrics.plain == nil, lyrics.synced == nil { return nil }
            return lyrics
        } catch APIError.http(404) {
            return nil
        }
    }

    // MARK: - Subtitles

    /// One caption track for a video.
    struct SubtitleTrack: Decodable, Sendable, Identifiable, Hashable {
        let id: Int
        let label: String
        let language: String
        let forced: Bool
        let sdh: Bool
        let `default`: Bool
        let url: URL
    }

    /// A video's caption tracks. Empty when there are none.
    func subtitles(itemID: Int) async throws -> [SubtitleTrack] {
        struct Response: Decodable { let subtitles: [SubtitleTrack] }
        do {
            let response: Response = try await send("/api/v1/items/\(itemID)/subtitles", method: "GET")
            return response.subtitles
        } catch APIError.http(404) {
            return []
        }
    }

    // MARK: - Reader (books)

    struct BookReader: Decodable, Sendable {
        struct Progress: Decodable, Sendable {
            let location: String?
            let percent: Int
            let finished: Bool
        }
        let id: Int
        let title: String
        let format: String
        let fileUrl: URL
        let progress: Progress?
    }

    /// A book's format and resume point.
    func reader(itemID: Int) async throws -> BookReader {
        try await send("/api/v1/items/\(itemID)/reader", method: "GET")
    }

    /// A book's reflowable text — ordered chapters the reader renders itself.
    /// `processing` while the server extracts (poll again), `empty` when there is
    /// no text, `ready` with the chapters.
    struct BookContent: Decodable, Sendable {
        struct Chapter: Decodable, Sendable, Identifiable, Hashable {
            let position: Int
            /// The source page (PDF); nil for EPUB, which has no fixed pages.
            let page: Int?
            let title: String?
            let text: String
            var id: Int { position }
        }
        /// An illustration, keyed to the page it belongs on, for inline placement.
        struct Image: Decodable, Sendable, Identifiable, Hashable {
            let page: Int
            let url: URL
            let width: Int?
            let height: Int?
            var id: URL { url }
        }
        let status: String
        let chapters: [Chapter]?
        let images: [Image]?
    }

    func readerContent(itemID: Int) async throws -> BookContent {
        try await send("/api/v1/items/\(itemID)/reader/content", method: "GET")
    }

    /// The URL of a book's file, for the reader to load with the bearer header.
    func bookURL(itemID: Int) -> URL? {
        baseURL.appendingPathComponent("/api/v1/items/\(itemID)/book")
    }

    /// Saves a reading position — an opaque location token and a percent.
    func saveReadingProgress(itemID: Int, location: String?, percent: Int) async throws {
        struct Body: Encodable { let location: String?; let percent: Int }
        _ = try await sendRaw("/api/v1/items/\(itemID)/reader/progress", method: "POST",
                              body: Body(location: location, percent: percent))
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
        // Fail fast rather than spin: a wrong scheme/host (e.g. https against a
        // plaintext LAN server) otherwise hangs on a TLS handshake that never
        // completes, which reads as "loads forever". 20s is generous for a LAN
        // or relay round-trip and short enough to surface an error.
        request.timeoutInterval = 20

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
            AppLog.warning("\(method) \(path) — unreachable: \(error.localizedDescription)", category: "net")
            throw APIError.unreachable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            AppLog.error("\(method) \(path) — non-HTTP response", category: "net")
            throw APIError.http(status: -1)
        }

        if http.statusCode == 401 {
            AppLog.warning("\(method) \(path) — 401 unauthorized", category: "net")
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            AppLog.warning("\(method) \(path) — HTTP \(http.statusCode)", category: "net")
            throw APIError.http(status: http.statusCode)
        }

        AppLog.debug("\(method) \(path) — \(http.statusCode)", category: "net")
        return data
    }

    /// A `multipart/form-data` POST carrying one file — for the playlist cover
    /// upload, which JSON can't express. One field, one file; that's all the
    /// server's `image` validation needs.
    private func sendMultipart(
        _ path: String,
        fileField: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        fields: [String: String] = [:]
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.badURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // An upload may be large, so a longer ceiling than a plain request, but
        // still bounded so a wrong host does not hang forever.
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // Any plain text fields first (e.g. an optional playlist name).
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        // Send the body with `upload(from:)`, not `httpBody` + `data(for:)`.
        // With `httpBody` on a POST, URLSession can stream the body chunked (no
        // Content-Length), and PHP-FPM then does not populate `$_FILES` — the
        // upload arrives but `request->file('cover')` is empty, so validation
        // says "cover is required" (a 422). `upload(from:)` sends a measured
        // body with a Content-Length, which the multipart parser needs.
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            throw APIError.unreachable(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.http(status: -1) }
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
