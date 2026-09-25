// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// What's downloaded on this device — playable with no connection.
///
/// Reads from the DownloadStore's sidecars, so it works offline and survives a
/// catalogue that hasn't loaded. Each row plays from the local file; the whole
/// list becomes the queue, so it plays through like any other screen.
struct DownloadsView: View {
    @Environment(DownloadStore.self) private var downloads
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No downloads yet",
                        systemImage: "arrow.down.circle",
                        description: Text("Downloaded songs play here without a connection.")
                    )
                } else {
                    List(Array(items.enumerated()), id: \.element.id) { pair in
                        Button {
                            // An expired row has no file behind it, so playing
                            // would fail silently. Tapping re-downloads with
                            // the same window instead (S-404).
                            if pair.element.isExpired {
                                redownload(pair.element)
                            } else {
                                playback.play(asMediaItems, startAt: pair.offset)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                DownloadArtwork(item: pair.element, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pair.element.title)
                                        .foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                                    if pair.element.isExpired {
                                        Text("Expired — tap to download again")
                                            .font(.caption)
                                            .foregroundStyle(SoundChexTheme.ink500)
                                            .lineLimit(1)
                                    } else if let subtitle = pair.element.subtitle {
                                        Text(subtitle).font(.caption)
                                            .foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
                                    }
                                }
                                Spacer()

                                // Expired, counting down, or simply stored
                                // (S-404). The expired row is deliberately
                                // still here: a film that vanished without
                                // trace is indistinguishable from one you
                                // never downloaded.
                                if pair.element.isExpired {
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(SoundChexTheme.ink500)
                                } else if let remaining = pair.element.timeRemaining {
                                    Text(Self.remainingLabel(remaining))
                                        .font(.caption2)
                                        .foregroundStyle(SoundChexTheme.ink500)
                                        .monospacedDigit()
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SoundChexTheme.storedGreen)
                                }
                            }
                            .contentShape(.rect)
                            .opacity(pair.element.isExpired ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SoundChexTheme.base900)
                        .swipeActions {
                            Button(role: .destructive) {
                                downloads.remove(pair.element.id)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Downloads")
            .background(SoundChexTheme.base900)
        }
    }

    /// Only the fully-stored items, most-recently-added first.
    private var items: [DownloadedItem] {
        downloads.stored.filter { downloads.isStored($0.id) }.reversed()
    }

    /// The downloaded entries as MediaItems, so the player can queue them.
    private var asMediaItems: [MediaItem] {
        items.map(\.asMediaItem)
    }
}

/// Artwork for a downloaded entry (which is a DownloadedItem, not a MediaItem).
private struct DownloadArtwork: View {
    let item: DownloadedItem
    var size: CGFloat

    var body: some View {
        Group {
            if let url = item.artwork {
                CachedImage(url: url) { $0.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(.rect(cornerRadius: 6))
    }

    private var placeholder: some View {
        SoundChexTheme.base700.overlay(
            Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500)
        )
    }
}

extension DownloadsView {
    /// "3d", "4h", "22m" — short enough to sit at the end of a row without
    /// pushing the title out, precise enough to act on.
    static func remainingLabel(_ remaining: TimeInterval) -> String {
        let hours = Int(remaining / 3600)

        if hours >= 24 { return "\(hours / 24)d" }
        if hours >= 1 { return "\(hours)h" }

        return "\(max(1, Int(remaining / 60)))m"
    }

    /// Queues an expired item again, keeping the window it originally had.
    private func redownload(_ item: DownloadedItem) {
        let retention: DownloadRetention = switch item.retentionSeconds {
        case .some(let seconds) where seconds <= 24 * 3600: .day
        case .some(let seconds) where seconds <= 3 * 24 * 3600: .threeDays
        case .some: .week
        case nil: .forever
        }

        downloads.download(item.asMediaItem, keeping: retention)
    }
}

extension DownloadedItem {
    /// A minimal MediaItem for playback — the id and metadata are all the player
    /// needs (it resolves the local file by id).
    var asMediaItem: MediaItem {
        MediaItem(
            id: id, type: type, title: title, subtitle: subtitle,
            parentID: nil, playable: true, artwork: artwork,
            meta: durationMs.map { MediaItem.Meta(durationMs: $0) }
        )
    }
}
