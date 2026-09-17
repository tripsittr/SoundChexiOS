// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Lyrics for the current track — shown only when the server has them.
///
/// Asks the lyrics endpoint (`GET /api/v1/items/{id}/lyrics`); if the server has
/// no lyrics for the song, nothing is shown at all — no empty "no lyrics" state,
/// per the design. Lyrics are fetched and cached by the server from a lyric API
/// (see the server-side LyricsService), so the app just reads what's there.
struct LyricsSection: View {
    @Environment(Session.self) private var session
    let item: MediaItem

    @State private var lyrics: String?

    var body: some View {
        Group {
            if let lyrics, !lyrics.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lyrics")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(SoundChexTheme.ink500)

                    Text(lyrics)
                        .font(.system(size: 16))
                        .foregroundStyle(SoundChexTheme.ink200)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 36)
            }
        }
        .task(id: item.id) {
            lyrics = nil
            lyrics = try? await session.api?.lyrics(itemID: item.id)
        }
    }
}
