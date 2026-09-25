// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The kebab on an album or artist page: act on the whole set at once (S-385).
///
/// Adding an album to a playlist used to mean adding every track by hand from
/// its row kebab. This is the same vocabulary as that menu — play next, add to
/// queue, add to playlist — applied to everything on the page.
///
/// Shared by both screens so the two cannot drift into offering different
/// actions for the same idea.
struct CollectionActions: View {
    @Environment(PlaybackController.self) private var playback

    /// The tracks this menu acts on, in the order they should queue.
    let tracks: [MediaItem]
    var onAddToPlaylist: () -> Void

    var body: some View {
        Menu {
            Button {
                playback.playNext(tracks)
            } label: {
                Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                playback.addToQueue(tracks)
            } label: {
                Label("Add to queue", systemImage: "text.append")
            }

            Button {
                onAddToPlaylist()
            } label: {
                Label("Add all to playlist", systemImage: "music.note.list")
            }

            // Deliberately no "Download all": the album page already has a
            // download button that reports what happened — not enough space,
            // nothing to do — and a menu entry discarding that result would be
            // the same action with worse feedback.
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(SoundChexTheme.ink200)
                .frame(width: 40, height: 40)
        }
        .disabled(tracks.isEmpty)
    }
}
