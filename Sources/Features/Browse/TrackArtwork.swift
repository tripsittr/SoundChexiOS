// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A track's cover, wearing the now-playing tell when it is the track playing
/// (S-362).
///
/// The equalizer-over-artwork and the accent title were written separately in
/// the library list, the album page and the artist page, and not at all in
/// search — so where a song appeared decided whether you could see it was the
/// one playing. One component now, used by every table, so "playing" looks the
/// same wherever a track is drawn.
struct TrackArtwork: View {
    @Environment(PlaybackController.self) private var playback

    let item: MediaItem
    var size: CGFloat = 48
    var aspect: CGFloat = 1

    /// Whether this is the track playing now.
    var isCurrent: Bool { playback.current?.id == item.id }

    var body: some View {
        Artwork(item: item, size: size, aspect: aspect)
            .overlay {
                if isCurrent {
                    SoundChexTheme.base900.opacity(0.55)
                        .clipShape(.rect(cornerRadius: 6))

                    // Still bars when paused: the track is current but nothing
                    // is moving, and animating then would say otherwise.
                    PlayingEqualizer(isAnimating: playback.isPlaying, size: size * 0.58)
                }
            }
    }
}

extension View {
    /// The accent colour a title takes while its track is playing (S-362).
    func nowPlayingTitle(_ isCurrent: Bool) -> some View {
        foregroundStyle(isCurrent ? SoundChexTheme.accent : SoundChexTheme.ink100)
    }
}
