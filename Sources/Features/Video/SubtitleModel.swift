// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Observation

/// Drives the video subtitle overlay (S-160).
///
/// Holds the available tracks, the chosen one's parsed cues, and the line to show
/// right now. The player's time observer calls `update(time:)`; the overlay reads
/// `currentLine`. Kept separate from the AVKit bridge so the caption logic is
/// plain, observable state.
@MainActor
@Observable
final class SubtitleModel {
    private(set) var tracks: [APIClient.SubtitleTrack] = []
    private(set) var selected: APIClient.SubtitleTrack?
    private(set) var currentLine: String?

    @ObservationIgnored private var vtt: WebVTT?
    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var itemID = 0

    func configure(api: APIClient?, itemID: Int) {
        self.api = api
        self.itemID = itemID
    }

    /// Loads the track list for the item. Off by default — captions show only
    /// once a track is chosen.
    func loadTracks() async {
        guard let api else { return }
        tracks = (try? await api.subtitles(itemID: itemID)) ?? []
    }

    /// Chooses a track (or turns captions off with nil) and loads its cues.
    func select(_ track: APIClient.SubtitleTrack?) async {
        selected = track
        currentLine = nil
        vtt = nil

        guard let track, let api else { return }

        // The .vtt is served on the token-authed route, so it needs the bearer
        // header — a plain URL load would 401.
        guard let content = await Self.fetchVTT(track.url, token: api.token) else { return }
        vtt = WebVTT.parse(content)
    }

    /// Updates the shown line for the current playback time.
    func update(time: TimeInterval) {
        guard let vtt else {
            if currentLine != nil { currentLine = nil }
            return
        }
        let line = vtt.cue(at: time)?.text
        if line != currentLine { currentLine = line }
    }

    /// Fetches WebVTT text with the bearer header.
    private static func fetchVTT(_ url: URL, token: String?) async -> String? {
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
