// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The full-screen player, opened by tapping the now-playing bar.
///
/// Big artwork, a working scrubber, the transport, and the up-next queue — the
/// native equivalent of the web now-playing sheet.
struct NowPlayingPage: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var addingToPlaylist = false

    var body: some View {
        ZStack {
            SoundChexTheme.base900.ignoresSafeArea()

            if let item = playback.current {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        Artwork(item: item, size: 300, aspect: 1)
                            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                            .padding(.top, 24)
                        titleBlock(item)
                        scrubber
                        transport
                        actionsRow(item)
                        LyricsSection(item: item)
                        upNextList
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .frame(width: 40, height: 40)
                    .background(SoundChexTheme.base800, in: .circle)
            }
            Spacer()
            Text("Now playing")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(SoundChexTheme.ink500)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 12)
    }

    private func titleBlock(_ item: MediaItem) -> some View {
        VStack(spacing: 4) {
            Text(item.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SoundChexTheme.ink100)
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(SoundChexTheme.ink400)
                    .lineLimit(1)
            }
        }
        .padding(.top, 28)
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : playback.position },
                    set: { scrubValue = $0 }
                ),
                in: 0...(max(playback.duration, 1)),
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { playback.seek(to: scrubValue) }
                }
            )
            .tint(SoundChexTheme.accent)

            HStack {
                Text(timeString(scrubbing ? scrubValue : playback.position))
                Spacer()
                Text(timeString(playback.duration))
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(SoundChexTheme.ink500)
        }
        .padding(.top, 24)
    }

    private var transport: some View {
        HStack(spacing: 32) {
            // Shuffle
            Button { playback.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18))
                    .foregroundStyle(playback.isShuffled ? SoundChexTheme.accent : SoundChexTheme.ink400)
            }

            Button { playback.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            Button { playback.togglePlayPause() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(SoundChexTheme.accent, in: .circle)
                    .shadow(color: SoundChexTheme.accent.opacity(0.4), radius: 12, y: 4)
            }
            Button { playback.next() } label: {
                Image(systemName: "forward.fill").font(.title2)
            }

            // Repeat: off / all / one
            Button { playback.cycleRepeat() } label: {
                Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 18))
                    .foregroundStyle(playback.repeatMode == .off ? SoundChexTheme.ink400 : SoundChexTheme.accent)
            }
        }
        .foregroundStyle(SoundChexTheme.ink200)
        .padding(.top, 24)
    }

    /// A row of secondary actions under the transport: download and the kebab.
    private func actionsRow(_ item: MediaItem) -> some View {
        HStack(spacing: 28) {
            // Persistent download control (wired to the download store in IOS-05).
            DownloadButton(item: item)

            Spacer()

            Menu {
                TrackActions(item: item, onAddToPlaylist: { addingToPlaylist = true })
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(SoundChexTheme.ink300)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 20)
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(item: item)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
    }

    @ViewBuilder private var upNextList: some View {
        let items = playback.upNext
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Up next")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(SoundChexTheme.ink500)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(items.prefix(20))) { item in
                    HStack(spacing: 12) {
                        Artwork(item: item, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline)
                                .foregroundStyle(SoundChexTheme.ink200).lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.caption)
                                    .foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.top, 36)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
