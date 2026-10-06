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

    /// What the file can do, and the synopsis — handed up by
    /// `MediaFactsSection`, which fetches the detail this page needs anyway.
    /// Asking for it twice would be the same request on every open.
    @State private var capabilities: [String] = []
    @State private var overview: String?

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

                    synopsis
                } else {
                    synopsis
                    episodeList
                }

                // Facts and credits: what the item is and who made it
                // (S-412). Below the episodes for a show, because someone
                // opening a series wants the next episode first.
                // The synopsis is drawn above, under the play button, so the
                // section does not repeat it.
                MediaFactsSection(
                    item: item,
                    onFacts: { badges, synopsis in
                        capabilities = badges
                        overview = synopsis
                    },
                    showsOverview: false,
                )
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

    /// The header, in the shape the streaming apps use.
    ///
    /// A wide backdrop running to the edges, then the title, the fact strip
    /// and the capability badges **left-aligned** beneath it.
    ///
    /// It was a centred 220pt poster under an "FILM" eyebrow. Three things
    /// were wrong with that: the poster is the image you just tapped, so
    /// repeating it small tells you nothing new; centred text stops the eye
    /// at every line where a page of left-aligned facts is scanned in one;
    /// and the eyebrow spent a whole line restating what the page obviously
    /// is. A backdrop earns the space because it is the only part of the
    /// header that is *about the film* rather than about the layout.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            backdrop

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title2.bold())
                    .foregroundStyle(SoundChexTheme.ink100)
                    .fixedSize(horizontal: false, vertical: true)

                factStrip

                if !capabilities.isEmpty {
                    capabilityStrip
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
    }

    /// The backdrop: full width, 16:9, fading into the page.
    ///
    /// The fade is what stops it reading as a pasted-in rectangle — the
    /// streaming apps all do it, and without it the join between image and
    /// page is a hard line across the screen.
    private var backdrop: some View {
        Artwork(item: item, size: 1, aspect: 0.5625, shape: .roundedSquare(0))
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fill)
            .frame(height: 210)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, SoundChexTheme.base900],
                    startPoint: .top,
                    endPoint: .bottom,
                )
                .frame(height: 90)
            }
            .accessibilityHidden(true)
    }

    /// The synopsis, directly under the primary action.
    ///
    /// Where the streaming apps put it, and for a good reason: having decided
    /// to press Play or not, the next question is "what is this" — not
    /// "who directed it", which is what sat here while the description was
    /// buried below the credits.
    ///
    /// Empty until the detail call returns, and nothing is reserved for it:
    /// a blank gap that later fills is worse than content arriving.
    @ViewBuilder
    private var synopsis: some View {
        if let overview, !overview.isEmpty {
            Text(overview)
                .font(.subheadline)
                .foregroundStyle(SoundChexTheme.ink300)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
    }

    /// What the file can do: 4K, Dolby Vision, 5.1, CC (#296).
    ///
    /// Beside the year and certificate because that is the same question —
    /// "what am I about to get" — and because an owner who ripped the 4K
    /// disc wants to see that the 4K is what is here.
    private var capabilityStrip: some View {
        HStack(spacing: 6) {
            ForEach(capabilities, id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .foregroundStyle(SoundChexTheme.ink300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(SoundChexTheme.base600, lineWidth: 1),
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quality: " + capabilities.joined(separator: ", "))
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

    /// Episodes, in the shape the streaming apps use: a season picker, and
    /// rows with a still, a duration and a synopsis.
    ///
    /// Was a number, a title and a chevron -- a file listing. See
    /// `EpisodeList` for why each of those four parts earns its place.
    private var episodeList: some View {
        EpisodeList(
            episodes: episodes,
            progress: episodeProgress,
            onPlay: { playing = $0 },
            onDownload: { downloadTarget = $0 },
        )
    }

    /// How far through each episode this viewer is, 0-1.
    ///
    /// Only for episodes with both a position and a known length: a fraction
    /// of an unknown duration is not a fraction, and a bar drawn from one
    /// would be a guess presented as fact. Taken from the item the server
    /// sent rather than from a separate call, so an episode list drawn from
    /// the offline cache keeps its bars.
    private var episodeProgress: [Int: Double] {
        var out: [Int: Double] = [:]

        for episode in episodes {
            guard let seconds = episode.resumePosition, seconds > 0,
                  let minutes = episode.meta?.runtimeMinutes, minutes > 0
            else { continue }

            out[episode.id] = min(Double(seconds) / Double(minutes * 60), 1)
        }

        return out
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
