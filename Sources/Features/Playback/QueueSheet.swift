// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The play queue, raised as a sheet from the now-playing player (S-288).
///
/// Spotify keeps "Now playing" and "Next up" here rather than inline under the
/// player. Queued tracks can be tapped to play, reordered, removed, or promoted
/// to play next.
struct QueueSheet: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = playback.current {
                    Section("Now playing") {
                        row(current, isCurrent: true)
                            .listRowBackground(SoundChexTheme.base900)
                    }
                }

                let next = playback.upNext
                if !next.isEmpty {
                    Section("Next up") {
                        ForEach(next) { item in
                            row(item, isCurrent: false)
                                .listRowBackground(SoundChexTheme.base900)
                                .contentShape(.rect)
                                .onTapGesture {
                                    playback.playFromQueue(itemID: item.id)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        playback.removeFromQueue(itemID: item.id)
                                    } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        playback.moveToPlayNext(itemID: item.id)
                                    } label: {
                                        Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    .tint(SoundChexTheme.accent)
                                }
                        }
                        .onMove(perform: playback.moveUpNext)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
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
    }
}
