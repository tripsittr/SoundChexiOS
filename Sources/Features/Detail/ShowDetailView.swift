// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A show or film: artwork header, and episodes grouped by season (for a show).
/// A film with no children just shows its own play/detail.
struct ShowDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(ThemeStore.self) private var theme
    @Environment(DownloadStore.self) private var downloads

    /// The episode whose retention is being chosen (S-404). Held here because
    /// the context menu that starts the flow cannot present a sheet itself.
    @State private var downloadTarget: MediaItem?
    let item: MediaItem

    /// The item to play in the video player, when one is tapped.
    @State private var playing: MediaItem?
    /// The book to open in the reader.
    @State private var reading: MediaItem?

    private var episodes: [MediaItem] { store.children(of: item.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if item.type == .book {
                    // A book opens the reader rather than the video player.
                    Button {
                        reading = item
                    } label: {
                        Label("Read", systemImage: "book")
                            .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                } else if episodes.isEmpty {
                    // A film, or a show with no episodes catalogued.
                    if item.playable {
                        HStack(spacing: 12) {
                            playButton(for: item, label: "Play")

                            // A film has no episode rows to hang a kebab off,
                            // so its download sits here. It still asks how
                            // long to keep it (S-404) — a film is the single
                            // largest thing this app will ever store.
                            if downloads.isStored(item.id) {
                                Button {
                                    downloads.remove(item.id)
                                } label: {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(SoundChexTheme.storedGreen)
                                        .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
                                }
                            } else {
                                Button {
                                    downloadTarget = item
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(SoundChexTheme.ink200)
                                        .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                } else {
                    episodeList
                }
            }
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(item.title)
        // Pushed screens do not inherit the tab root's inset, so the last
        // row would sit under the now-playing bar (S-343).
        .nowPlayingInset()
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { toPlay in
            VideoPlayerView(item: toPlay).soundchexTheme(theme)
        }
        .sheet(item: $downloadTarget) { episode in
            RetentionPicker(title: episode.meta?.episodeTitle ?? episode.title) { retention in
                downloads.download(episode, keeping: retention)
            }
            .presentationDetents([.medium])
            .soundchexTheme(theme)
        }
        .fullScreenCover(item: $reading) { toRead in
            NavigationStack { ReaderView(item: toRead) }.soundchexTheme(theme)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Artwork(item: item, size: 220, aspect: 1.5)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            Text(eyebrow)
                .font(.caption2.bold()).tracking(1.5)
                .foregroundStyle(SoundChexTheme.ink500)
            Text(item.title).font(.title3.bold()).foregroundStyle(SoundChexTheme.ink100)
                .multilineTextAlignment(.center)
            if let meta = metaLine {
                Text(meta).font(.subheadline).foregroundStyle(SoundChexTheme.ink500)
            }
        }
        .padding(.top, 12)
    }

    private var eyebrow: String {
        episodes.isEmpty ? "Film" : "Show"
    }

    /// "2024 · 3 seasons" for a show, "2024" for a film, or the subtitle — the
    /// "·"-joined meta line, skipping missing parts.
    private var metaLine: String? {
        var parts: [String] = []
        if let year = item.meta?.releaseYear { parts.append(String(year)) }
        if !episodes.isEmpty {
            let seasons = Set(episodes.compactMap { $0.meta?.seasonNumber }).count
            if seasons > 0 { parts.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
        } else if let subtitle = item.subtitle {
            parts.append(subtitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedBySeason, id: \.season) { group in
                if group.season > 0 {
                    Text("Season \(group.season)")
                        .font(.system(size: 13, weight: .semibold)).tracking(1).textCase(.uppercase)
                        .foregroundStyle(SoundChexTheme.ink500)
                        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
                }
                ForEach(group.episodes) { episode in
                    Button {
                        playing = episode
                    } label: {
                        HStack(spacing: 12) {
                            if let n = episode.meta?.episodeNumber {
                                Text("\(n)").font(.subheadline.monospacedDigit())
                                    .foregroundStyle(SoundChexTheme.ink500).frame(width: 28)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.meta?.episodeTitle ?? episode.title)
                                    .foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                            }
                            Spacer()

                            // Stored episodes say so on the row; downloading
                            // is in the kebab rather than a button of its own
                            // (S-388). The owner's call, and the right one:
                            // an episode is gigabytes, and a download control
                            // on every row of a 60-episode series is an
                            // invitation to fill a phone by accident. There
                            // is deliberately no season or series
                            // download-all for the same reason.
                            if downloads.isStored(episode.id) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(SoundChexTheme.storedGreen)
                            }

                            Image(systemName: "play.circle").foregroundStyle(SoundChexTheme.ink400)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        EpisodeActions(episode: episode) { downloadTarget = $0 }
                    }
                    Divider().overlay(SoundChexTheme.base700).padding(.leading, 56)
                }
            }
        }
    }

    private func playButton(for item: MediaItem, label: String) -> some View {
        Button {
            playing = item
        } label: {
            Label(label, systemImage: "play.fill")
                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
        }
    }

    /// Episodes grouped by season number, in order.
    private var groupedBySeason: [(season: Int, episodes: [MediaItem])] {
        let groups = Dictionary(grouping: episodes) { $0.meta?.seasonNumber ?? 0 }
        return groups.keys.sorted().map { season in
            (season, groups[season]!.sorted { ($0.meta?.episodeNumber ?? 0) < ($1.meta?.episodeNumber ?? 0) })
        }
    }
}

/// The per-episode actions, in a long-press menu rather than a row of buttons
/// (S-388).
///
/// An episode is gigabytes. Putting a download control on every row of a
/// 60-episode series — or a "download this season" button above it — makes
/// filling a phone a one-tap mistake, so downloading an episode is a
/// deliberate act you have to go looking for. Video also asks how long to
/// keep it (S-404), which is what makes that choice low-stakes.
private struct EpisodeActions: View {
    @Environment(DownloadStore.self) private var downloads

    let episode: MediaItem

    /// Asks the parent to present the picker. A context menu is dismissed
    /// before a sheet attached to it would appear, so the sheet has to belong
    /// to the view the menu hangs off.
    let onDownload: (MediaItem) -> Void

    var body: some View {
        if downloads.isStored(episode.id) {
            Button(role: .destructive) {
                downloads.remove(episode.id)
            } label: {
                Label("Remove download", systemImage: "trash")
            }
        } else {
            Button {
                onDownload(episode)
            } label: {
                Label("Download episode", systemImage: "arrow.down.circle")
            }
        }
    }
}
