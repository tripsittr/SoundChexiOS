// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The play queue, raised as a sheet from the now-playing player (S-288).
///
/// Spotify keeps "Now playing" and "Next up" here rather than inline under the
/// player. Tapping a queued track jumps to it. Read-only reordering is deliberate
/// for now — the queue model is index-based and a drag-to-reorder would need the
/// controller to expose a move; that can come later without changing this shell.
struct QueueSheet: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let current = playback.current {
                        section("Now playing") {
                            row(current, isCurrent: true)
                        }
                    }

                    let next = playback.upNext
                    if !next.isEmpty {
                        section("Next up") {
                            ForEach(Array(next.prefix(50))) { item in
                                row(item, isCurrent: false)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(SoundChexTheme.base900)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SoundChexTheme.ink200)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(SoundChexTheme.ink500)
            content()
        }
    }

    private func row(_ item: MediaItem, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Artwork(item: item, size: 48)
                .overlay {
                    if isCurrent {
                        SoundChexTheme.base900.opacity(0.55).clipShape(.rect(cornerRadius: 6))
                        PlayingEqualizer(isAnimating: playback.isPlaying, size: 28)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(isCurrent ? SoundChexTheme.accent : SoundChexTheme.ink100)
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
}
