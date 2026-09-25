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
    /// The song the Add to Playlist sheet was opened for.
    ///
    /// Held rather than read from `playback.current`: the track changes while
    /// the sheet is open — that is the whole point of a player — and the sheet
    /// was silently re-targeting the new song, so you added whatever happened
    /// to be playing when you tapped, not the song you opened it for (S-374).
    @State private var addingToPlaylist: MediaItem?
    @State private var showingQueue = false
    @State private var showingLyrics = false

    var body: some View {
        ZStack {
            SoundChexTheme.base900.ignoresSafeArea()

            if let item = playback.current {
                // Spotify's player is a fixed layout, not a long scroll: art,
                // title, scrubber and transport fill the screen, with Lyrics and
                // the queue raised as their own sheets from the bottom bar.
                VStack(spacing: 0) {
                    header(item)
                    Spacer(minLength: 12)
                    Artwork(item: item, size: artworkSide, aspect: 1)
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                    Spacer(minLength: 12)
                    titleBlock(item)
                    scrubber
                    transport
                    bottomBar(item)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .sheet(isPresented: $showingQueue) {
                    QueueSheet()
                        .presentationDetents([.medium, .large])
                        .soundchexTheme(theme)
                }
                .sheet(isPresented: $showingLyrics) {
                    // The background goes behind the sheet, not behind the
                    // content: a ScrollView sizes to what it holds, so while
                    // the lyrics were still loading it painted a thin strip
                    // across the top of an otherwise transparent sheet (S-338).
                    ScrollView {
                        LyricsSection(item: item)
                            .padding(20)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SoundChexTheme.base900)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(SoundChexTheme.base900)
                    .soundchexTheme(theme)
                }
            }
        }
    }

    /// The artwork side — most of the width, capped so it never crowds the
    /// controls on a short screen.
    private var artworkSide: CGFloat {
        min(UIScreen.main.bounds.width - 56, 360)
    }

    private func header(_ item: MediaItem) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .frame(width: 40, height: 40)
                    .background(SoundChexTheme.base800, in: .circle)
            }
            Spacer()
            // "PLAYING FROM <ALBUM>" — the context line, derived from the track's
            // album since the queue carries no separate source label.
            VStack(spacing: 2) {
                Text("Playing from")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(SoundChexTheme.ink500)
                if let context = playbackContext(item) {
                    MarqueeText(
                        text: context,
                        font: .system(size: 12, weight: .semibold),
                        color: SoundChexTheme.ink200,
                        lineHeight: 16,
                        alignment: .center,
                    )
                }
            }
            Spacer()
            Menu {
                TrackActions(item: item, onAddToPlaylist: { addingToPlaylist = item })
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.top, 12)
        .sheet(item: $addingToPlaylist) { pinned in
            AddToPlaylistSheet(item: pinned)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
    }

    /// The album (or author) the current track belongs to, for the context line.
    private func playbackContext(_ item: MediaItem) -> String? {
        if let album = item.meta?.album, !album.isEmpty { return album }
        return item.subtitle
    }

    private func titleBlock(_ item: MediaItem) -> some View {
        HStack(alignment: .center) {
            // Left-aligned, Spotify-style — not centred.
            VStack(alignment: .leading, spacing: 4) {
                // Scrolled rather than truncated: a long title cut to
                // "The Road to Hell Is Highway 59 (feat…" hides the part that
                // says which track it is (S-377).
                MarqueeText(
                    text: item.title,
                    font: .system(size: 22, weight: .bold),
                    color: SoundChexTheme.ink100,
                    lineHeight: 27,
                )
                if let subtitle = item.subtitle {
                    MarqueeText(
                        text: subtitle,
                        font: .system(size: 16),
                        color: SoundChexTheme.ink300,
                        lineHeight: 20,
                    )
                }
            }
            Spacer()
            // Download stands in for Spotify's save/heart — the app has no
            // like/favourite concept, and inventing one needs a server endpoint
            // (out of scope for the redesign). Download is the real "keep this".
            DownloadButton(item: item, size: 22)
        }
        .padding(.top, 24)
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
            // A new song releases the scrubber. `scrubbing` is only cleared by
            // the Slider's editing-ended callback, and a track change while it
            // is held — or a gesture whose end is never reported — left the
            // view showing the old `scrubValue` and ignoring `position`
            // entirely: the audio restarted while the thumb stayed frozen at
            // the time it was dragged to (S-342).
            .onChange(of: playback.current?.id) { _, _ in
                scrubbing = false
                scrubValue = 0
            }

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

    /// What VoiceOver says the shuffle button will do next.
    private var shuffleLabel: String {
        switch playback.shuffleMode {
        case .off: "Shuffle"
        case .on: "Shuffle on. Press for smart shuffle"
        case .smart: "Smart shuffle on"
        }
    }

    private var transport: some View {
        HStack(spacing: 32) {
            // Shuffle: off → on → smart, on one button (S-289). Smart gets
            // its own glyph rather than a badge — iOS ships one, and a
            // sparkle reads as "chosen for you" without a legend.
            Button { playback.toggleShuffle() } label: {
                Image(systemName: playback.shuffleMode == .smart ? "shuffle.circle.fill" : "shuffle")
                    .font(.system(size: 18))
                    .foregroundStyle(playback.isShuffled ? SoundChexTheme.accent : SoundChexTheme.ink400)
            }
            .accessibilityLabel(shuffleLabel)

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

    /// The bottom bar under the transport: Lyrics and the queue, each raising its
    /// own sheet — Spotify keeps them off the main player rather than inline.
    private func bottomBar(_ item: MediaItem) -> some View {
        HStack {
            Button { showingLyrics = true } label: {
                Label("Lyrics", systemImage: "quote.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SoundChexTheme.ink300)
            }
            Spacer()
            // AirPlay. The audio already routes — the session is long-form
            // playback — so this is the picker that was missing (S-165).
            RoutePickerButton(
                tint: UIColor(SoundChexTheme.ink300),
                activeTint: UIColor(SoundChexTheme.accent),
            )
            .frame(width: 28, height: 28)
            .accessibilityLabel("AirPlay")
            Spacer()
            Button { showingQueue = true } label: {
                Label("Queue", systemImage: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SoundChexTheme.ink300)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 22)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
