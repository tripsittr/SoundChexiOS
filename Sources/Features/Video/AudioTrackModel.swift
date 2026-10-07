// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import AVFoundation
import Foundation

/// Which audio track is playing, and what else is on offer.
///
/// There are two ways a track gets chosen, because there are two ways a file
/// gets played:
///
///  - **Direct play.** The file carries all its tracks and `AVPlayer` can
///    switch between them itself through `AVMediaSelectionGroup`. Instant, no
///    server involvement, no re-buffer.
///  - **Transcoded.** The stream contains exactly one audio track, because
///    that is what `-map 0:a:N` produced. Switching means asking the server
///    for a different stream, which restarts playback at the same position.
///
/// The menu looks the same either way; what happens underneath does not.
/// Keeping both behind one type is what stops every caller having to know
/// which kind of playback it is looking at.
@MainActor
@Observable
final class AudioTrackModel {
    struct Track: Identifiable, Equatable {
        /// The index the server uses for `?audio=N`, or the position in the
        /// asset's selection group for direct play.
        let id: Int
        let label: String
        /// The selection option, for direct play only. Transcoded streams
        /// have nothing to select locally.
        let option: AVMediaSelectionOption?
    }

    private(set) var tracks: [Track] = []
    private(set) var selected: Int?

    /// Whether switching costs a reload.
    ///
    /// True for a transcoded stream, where the server has to encode a
    /// different one. The menu says so, because a switch that silently
    /// restarts playback looks like a bug.
    private(set) var switchingReloads = false

    private var player: AVPlayer?

    /// The asset's audio selection group, kept from the load.
    ///
    /// Held rather than fetched at selection time: the synchronous
    /// `mediaSelectionGroup(forMediaCharacteristic:)` is deprecated, and its
    /// replacement is async -- which `select` cannot be, because it answers
    /// "did this switch happen in place" and the caller needs that now.
    /// Loading it once, asynchronously, and keeping it is the honest way to
    /// have both.
    private var group: AVMediaSelectionGroup?

    /// Reads the tracks the **asset** carries, for a directly played file.
    ///
    /// Returns false when the asset has no audio selection group — a
    /// transcoded stream carries one track, so there is nothing to choose and
    /// the server's list is used instead.
    func loadFromAsset(player: AVPlayer) async -> Bool {
        self.player = player

        guard let asset = (player.currentItem?.asset as? AVURLAsset) else { return false }

        guard let group = try? await asset.loadMediaSelectionGroup(for: .audible),
              group.options.count > 1
        else { return false }

        self.group = group

        tracks = group.options.enumerated().map { index, option in
            Track(id: index, label: Self.label(for: option), option: option)
        }

        switchingReloads = false

        // Whatever the player already chose, so the menu opens on the truth
        // rather than on a guess.
        if let current = player.currentItem?.currentMediaSelection.selectedMediaOption(in: group),
           let index = group.options.firstIndex(of: current) {
            selected = index
        } else {
            selected = 0
        }

        return true
    }

    /// Uses the list the server sent, for a transcoded stream.
    func loadFromServer(_ serverTracks: [APIClient.AudioTrack], selected index: Int) {
        guard serverTracks.count > 1 else {
            tracks = []

            return
        }

        tracks = serverTracks.map { Track(id: $0.index, label: $0.label, option: nil) }
        switchingReloads = true
        selected = index
    }

    /// Switches track, where the asset can do it locally.
    ///
    /// Returns false when the caller has to reload instead — a transcoded
    /// stream cannot switch in place, because the track it would switch to is
    /// not in the stream.
    func select(_ track: Track) -> Bool {
        selected = track.id

        guard let option = track.option,
              let item = player?.currentItem,
              let group
        else { return false }

        item.select(option, in: group)

        return true
    }

    /// What to call one of the asset's own options.
    ///
    /// Language and channel count, the same shape the server uses, so the two
    /// paths read identically in the menu. `displayName` alone is often just
    /// "Audio" for a track with no title.
    private static func label(for option: AVMediaSelectionOption) -> String {
        var parts: [String] = []

        if let language = option.locale?.localizedString(forLanguageCode: option.locale?.language.languageCode?.identifier ?? "") {
            parts.append(language)
        } else if let name = option.locale?.identifier {
            parts.append(name.uppercased())
        }

        // The display name carries "Commentary" and similar where the file
        // bothered to say so, which is worth keeping.
        let name = option.displayName

        if !name.isEmpty, !parts.contains(name), name.lowercased() != "audio" {
            parts.append(name)
        }

        return parts.isEmpty ? "Audio track" : parts.joined(separator: " · ")
    }
}
