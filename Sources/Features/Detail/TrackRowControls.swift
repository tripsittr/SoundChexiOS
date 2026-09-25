// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The download indicator and kebab that belong on every track row (S-390).
///
/// The Songs list has had both for a while; the album track list and the
/// artist's Popular list were custom rows with neither. So downloading an
/// album gave no per-track feedback at all — which is how a download that was
/// working got reported as failing.
///
/// Shared, so the three lists cannot drift into showing different controls for
/// the same row.
struct TrackRowControls: View {
    @Environment(ThemeStore.self) private var theme

    let item: MediaItem

    @State private var addingToPlaylist = false

    var body: some View {
        HStack(spacing: 4) {
            DownloadButton(item: item, size: 18)

            Menu {
                TrackActions(item: item, onAddToPlaylist: { addingToPlaylist = true })
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .foregroundStyle(SoundChexTheme.ink500)
                    .frame(width: 32, height: 40)
                    .contentShape(.rect)
            }
        }
        // The row itself is a button that starts playback, so the controls
        // must not pass their taps up to it.
        .buttonStyle(.plain)
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(item: item)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
    }
}
