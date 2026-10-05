// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The persistent now-playing bar, docked above the tab bar while something
/// plays. Tapping it opens the full-screen player.
struct NowPlayingBar: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(ThemeStore.self) private var theme
    @State private var showingPlayer = false

    var body: some View {
        if let item = playback.current {
            VStack(spacing: 0) {
                progressTrack

                HStack(spacing: 12) {
                    // The info area opens the full-screen player; the transport
                    // buttons keep their own taps.
                    Button {
                        showingPlayer = true
                    } label: {
                        HStack(spacing: 12) {
                            Artwork(item: item, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SoundChexTheme.ink100)
                                    .lineLimit(1)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(SoundChexTheme.ink500)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    // One element, not three. Read separately, VoiceOver
                    // announces the artwork, then the title, then the
                    // subtitle, and never says any of it is a button.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(nowPlayingLabel(for: item))
                    .accessibilityHint("Opens the full player")
                    .accessibilityAddTraits(.isButton)

                    Button { playback.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .accessibilityLabel("Previous")

                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    // The label changes with the state, so VoiceOver describes
                    // what the tap will do rather than what is happening now.
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                    Button { playback.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .accessibilityLabel("Next")
                }
                .foregroundStyle(SoundChexTheme.ink100)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // The web's fill, not Apple's material (S-449). `.mobile-tabs`
            // uses base-800 at 94% with a hairline above it — a flat panel
            // with a little of the page showing through, rather than a blur
            // that takes its colour from whatever scrolls underneath.
            //
            // This also retires the Reduce Transparency branch added in #437:
            // there is no longer a blur to opt out of, so the setting and the
            // default now agree instead of diverging.
            .background(SoundChexTheme.base800.opacity(0.94))
            .overlay(alignment: .top) {
                // base-600, which is what the web draws. This was base-700 —
                // a shade too dark to read as an edge against the bar itself.
                Rectangle().fill(SoundChexTheme.base600).frame(height: 0.5)
            }
            .fullScreenCover(isPresented: $showingPlayer) {
                NowPlayingPage().soundchexTheme(theme)
            }
        }
    }

    /// What VoiceOver says for the info area: the track, then who it is by,
    /// then that it is playing — the same three things a sighted person takes
    /// from the bar at a glance.
    private func nowPlayingLabel(for item: MediaItem) -> String {
        var parts = ["Now playing", item.title]

        if let subtitle = item.subtitle, !subtitle.isEmpty {
            parts.append("by \(subtitle)")
        }

        if !playback.isPlaying {
            parts.append("paused")
        }

        return parts.joined(separator: ", ")
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            let fraction = playback.duration > 0 ? playback.position / playback.duration : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(SoundChexTheme.base700)
                Rectangle().fill(SoundChexTheme.accent)
                    .frame(width: geo.size.width * fraction)
            }
            // A two-point bar is not a touch target, but how far through you
            // are is real information, and colour is the only thing carrying
            // it. Stated as a percentage so it survives both VoiceOver and
            // Differentiate Without Colour.
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        }
        .frame(height: 2)
    }
}
