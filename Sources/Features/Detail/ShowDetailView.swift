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
                    // A book opens the reader rather than the video player,
                    // and can be downloaded to read with no server — which it
                    // could not be before, having had no download control
                    // anywhere in the app (S-416).
                    HStack(spacing: 12) {
                        Button {
                            reading = item
                        } label: {
                            Label("Read", systemImage: "book")
                                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
                        }

                        // No retention prompt: a book is a few megabytes, and
                        // asking how long to keep one would be the tax on
                        // every tap that S-404 deliberately avoided for music.
                        DownloadButton(item: item, size: 20)
                    }
                    .buttonStyle(.plain)
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
                                        .accessibilityLabel("Downloaded. Remove download")
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
                                        .accessibilityLabel("Download")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                } else {
                    episodeList
                }

                // Facts and credits: what the item is and who made it
                // (S-412). Below the episodes for a show, because someone
                // opening a series wants the next episode first.
                MediaFactsSection(item: item)
                    .padding(.top, 8)
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

            // The fact strip, in the shape the streaming apps use: year, the
            // certificate in a box, then the length. A boxed rating reads as a
            // classification rather than as another word in a sentence, which
            // is the point of the box.
            factStrip
        }
        .padding(.top, 12)
    }

    private var eyebrow: String {
        episodes.isEmpty ? "Film" : "Show"
    }

    /// "2024 · 3 seasons" for a show, "2024" for a film, or the subtitle — the
    /// "·"-joined meta line, skipping missing parts.
    /// Year, certificate and length, as a row rather than a sentence.
    ///
    /// Replaces a `·`-joined string. The pieces are different kinds of thing --
    /// a number, a classification, a duration -- and running them together made
    /// the certificate read as another word rather than as a rating.
    private var factStrip: some View {
        HStack(spacing: 10) {
            if let year = item.meta?.releaseYear {
                Text(String(year))
            }

            if let certificate = item.meta?.mpaaRating ?? item.meta?.contentRating {
                Text(certificate)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(SoundChexTheme.ink500.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
            }

            if let length = lengthLabel {
                Text(length)
            }
        }
        .font(.subheadline)
        .foregroundStyle(SoundChexTheme.ink300)
        // Read as one line rather than three unrelated fragments.
        .accessibilityElement(children: .combine)
    }

    /// "1h 23m" for a film, "11 Seasons" for a show.
    ///
    /// Hours and minutes rather than "83 min", which is how long a film is in
    /// every place a person has seen one described. A show's length is its
    /// season count: nobody asks how many minutes a series runs to.
    private var lengthLabel: String? {
        if !episodes.isEmpty {
            let seasons = Set(episodes.compactMap { $0.meta?.seasonNumber }).count

            return seasons > 0 ? "\(seasons) Season\(seasons == 1 ? "" : "s")" : nil
        }

        guard let minutes = item.meta?.runtimeMinutes, minutes > 0 else {
            return item.subtitle
        }

        let hours = minutes / 60
        let rest = minutes % 60

        if hours == 0 {
            return "\(rest)m"
        }

        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

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
                        .font(ScaledFont.system(size: 13, relativeTo: .footnote, weight: .semibold)).tracking(1).textCase(.uppercase)
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
                                    .foregroundStyle(SoundChexTheme.ink100).scalableTitle()
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
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    // The number, the title and — if it is on the device — a
                    // green tick, as one sentence. The tick is the only mark
                    // of a downloaded episode, so it has to be said.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(episodeLabel(episode))
                    .accessibilityAddTraits(.isButton)
                    .contextMenu {
                        EpisodeActions(episode: episode) { downloadTarget = $0 }
                    }
                    Divider().overlay(SoundChexTheme.base700).padding(.leading, 56)
                }
            }
        }
    }

    /// An episode row, spoken.
    private func episodeLabel(_ episode: MediaItem) -> String {
        var parts: [String] = []

        if let number = episode.meta?.episodeNumber {
            parts.append("Episode \(number)")
        }

        parts.append(episode.meta?.episodeTitle ?? episode.title)

        if downloads.isStored(episode.id) {
            parts.append("Downloaded")
        }

        return parts.joined(separator: ", ")
    }

    /// The primary action, weighted like one.
    ///
    /// White on black rather than tinted: on a page that is mostly artwork and
    /// dark surfaces, the accent colour competes with the poster while white
    /// does not. It is the one thing somebody came to the page to press.
    private func playButton(for item: MediaItem, label: String) -> some View {
        Button {
            playing = item
        } label: {
            Label(label, systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: .capsule)
                .foregroundStyle(.black)
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
