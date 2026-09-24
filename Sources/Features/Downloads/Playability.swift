// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Whether a track can actually be played at this moment (S-362).
///
/// One rule, asked by every row that draws one, so search, the library and a
/// playlist cannot drift apart on the answer. Offline, a track the device does
/// not hold cannot play: the row is dimmed and refuses the tap rather than
/// accepting it and failing in silence, which is what made downloads look
/// broken when the real problem was that nothing had been downloaded.
enum Playability {
    /// Playable now: either the bytes are here, or the network is.
    @MainActor
    static func canPlay(_ item: MediaItem, downloads: DownloadStore, online: Bool) -> Bool {
        // Something with no file behind it — a wishlist row — can never play.
        guard item.playable else { return false }

        return online || downloads.isStored(item.id)
    }

    /// Why it cannot, for a row to say so. Nil when it can.
    @MainActor
    static func reason(_ item: MediaItem, downloads: DownloadStore, online: Bool) -> String? {
        if canPlay(item, downloads: downloads, online: online) { return nil }

        return item.playable ? "Not downloaded" : "Not available"
    }
}

extension View {
    /// Dims a row and stops it responding when its track cannot play (S-362).
    ///
    /// `allowsHitTesting(false)` rather than `.disabled()`: disabling a row
    /// would also disable the kebab inside it, and the actions that *do* work
    /// offline — remove a download, add to a playlist — are exactly the ones
    /// someone reaches for when a track will not play.
    func playableRow(_ canPlay: Bool) -> some View {
        opacity(canPlay ? 1 : 0.45)
            .allowsHitTesting(canPlay)
    }
}
