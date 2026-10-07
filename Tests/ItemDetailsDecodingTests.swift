// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Testing

@testable import SoundChex

/// Decoding a real `/items/{id}/details` response.
///
/// **Three bugs of one kind have shipped from this area**, each invisible
/// until somebody looked at a device weeks later. Every decoded field is
/// optional, so a `CodingKeys` spelling that matches nothing returns nil and
/// reads as missing data rather than as a fault:
///
///  - **#89 → #91** — `ItemFacts` keys written in the wire's snake_case while
///    the decoder applies `.convertFromSnakeCase`. By the time matching
///    happens `imdb_rating` is already `imdbRating`, so `case imdbRating =
///    "imdb_rating"` matched nothing. It took IMDb, Rotten Tomatoes, runtime,
///    file size, season and episode counts, the content rating and `addedAt`
///    with it.
///  - **#94** — `capabilities` and `audio_tracks` declared on `ItemFacts`,
///    which decodes the nested `detail` object, when the server sends both at
///    the **top level**. The capability badges never once appeared.
///
/// The payload below is the server's real shape, taken from
/// `MediaController::details()`. These assertions are deliberately about
/// *values arriving*, not about the struct's design: a test that only checks
/// the type compiles would have passed through all three bugs.
struct ItemDetailsDecodingTests {
    /// The shape `/api/v1/items/{id}/details` actually returns.
    private static let payload = """
    {
      "id": 1368,
      "overview": "Clancy explores existential questions.",
      "cast": [{"id": 1, "name": "Duncan Trussell", "role": "Clancy"}],
      "crew": [{"id": 2, "name": "Pendleton Ward", "role": "Creator"}],
      "tags": ["animation"],
      "genres": ["Animation", "Comedy"],
      "capabilities": ["4K", "Dolby Vision", "5.1", "CC"],
      "audio_tracks": [
        {"index": 0, "label": "English 5.1", "language": "eng", "channels": 6, "codec": "ac3", "default": true},
        {"index": 1, "label": "Japanese Stereo", "language": "jpn", "channels": 2, "codec": "aac", "default": false}
      ],
      "detail": {
        "type": "show",
        "year": 2020,
        "runtime_minutes": 24,
        "season_count": 1,
        "episode_count": 8,
        "content_rating": "TV-MA",
        "imdb_rating": 8.1,
        "imdb_votes": 32000,
        "rt_score": 83,
        "metascore": 76,
        "awards": "Nominated for 2 Annie Awards",
        "file_size": 1073741824,
        "added_at": "2026-10-06T12:00:00+00:00",
        "director": "Pendleton Ward",
        "studio": "Titmouse",
        "language": "en",
        "country": "US"
      }
    }
    """

    /// Decoded exactly as `APIClient` does, or the test proves nothing about
    /// the real path.
    private func decoded() throws -> APIClient.DetailsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(
            APIClient.DetailsResponse.self,
            from: Data(Self.payload.utf8),
        )
    }

    // MARK: - The top-level keys (#94)

    @Test("capabilities decode from the response's top level")
    func capabilitiesDecode() throws {
        let response = try decoded()

        #expect(response.capabilities == ["4K", "Dolby Vision", "5.1", "CC"])
    }

    @Test("audio tracks decode from the response's top level")
    func audioTracksDecode() throws {
        let response = try decoded()

        #expect(response.audioTracks?.count == 2)
        #expect(response.audioTracks?.first?.label == "English 5.1")
        #expect(response.audioTracks?.first?.isDefault == true)
        #expect(response.audioTracks?.last?.index == 1)
    }

    // MARK: - The nested facts (#89 → #91)

    @Test("every underscored fact decodes")
    func underscoredFactsDecode() throws {
        let facts = try #require(try decoded().detail)

        // Each of these returned nil before #91, and each looked like a gap
        // in the data rather than a bug.
        #expect(facts.imdbRating == 8.1)
        #expect(facts.imdbVotes == 32000)
        #expect(facts.rtScore == 83)
        #expect(facts.runtimeMinutes == 24)
        #expect(facts.seasonCount == 1)
        #expect(facts.episodeCount == 8)
        #expect(facts.contentRating == "TV-MA")
        #expect(facts.fileSize == 1_073_741_824)
        #expect(facts.addedAt == "2026-10-06T12:00:00+00:00")
    }

    @Test("fields without underscores still decode")
    func plainFactsDecode() throws {
        let facts = try #require(try decoded().detail)

        // `metascore` was the one key that survived #91, precisely because it
        // has no underscore -- which is what made the bug look like missing
        // data rather than a decoding fault.
        #expect(facts.metascore == 76)
        #expect(facts.year == 2020)
        #expect(facts.director == "Pendleton Ward")
        #expect(facts.awards == "Nominated for 2 Annie Awards")
    }

    // MARK: - Tolerance

    @Test("an older server's response still decodes")
    func sparseResponseDecodes() throws {
        // Every field is optional on purpose: a server that predates a key
        // must not break the screen. That tolerance is also what hid the
        // bugs above, so it is worth asserting it is intentional.
        let sparse = #"{"id":1,"cast":[],"crew":[],"tags":[]}"#

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(
            APIClient.DetailsResponse.self,
            from: Data(sparse.utf8),
        )

        #expect(response.capabilities == nil)
        #expect(response.detail == nil)
    }
}
