// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Episodes, in the shape the streaming apps use.
///
/// What was here before was a file listing: a number, a title, a chevron. The
/// layout every streaming app settled on instead gives each episode a **still**,
/// a **duration** and a **sentence about what happens**, under a **season
/// picker** rather than an endless scroll through every season at once.
///
/// That shape is not decoration. A series with sixty episodes is unusable as
/// one list, and an episode title on its own ("Aunt Ginger") tells you nothing
/// about whether you have seen it. The still is the strongest cue of the four —
/// recognising a frame is faster than reading a synopsis.
struct EpisodeList: View {
    let episodes: [MediaItem]
    /// How far through each episode the viewer is, 0–1, for the progress bar
    /// under its still. Absent for anything unwatched.
    var progress: [Int: Double] = [:]
    let onPlay: (MediaItem) -> Void
    let onDownload: (MediaItem) -> Void

    @Environment(DownloadStore.self) private var downloads

    /// The season on screen. Starts at the first one that has anything.
    @State private var season: Int?

    private var seasons: [Int] {
        Array(Set(episodes.compactMap(\.meta?.seasonNumber))).sorted()
    }

    /// The chosen season, or the first available — resolved here rather than
    /// seeded in `onAppear`, so the list is never briefly empty on the way in.
    private var shownSeason: Int? {
        season ?? seasons.first
    }

    private var shown: [MediaItem] {
        let inSeason = episodes.filter { episode in
            // A series whose episodes carry no season number at all is one
            // flat list rather than nothing: the picker hides itself below.
            guard let season = shownSeason else { return true }

            return episode.meta?.seasonNumber == season
        }

        return inSeason.sorted {
            ($0.meta?.episodeNumber ?? .max) < ($1.meta?.episodeNumber ?? .max)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if seasons.count > 1 {
                picker
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { episode in
                    EpisodeRow(
                        episode: episode,
                        progress: progress[episode.id],
                        onPlay: { onPlay(episode) },
                        onDownload: { onDownload(episode) },
                    )

                    Divider().overlay(SoundChexTheme.base700)
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// The season picker: a menu rather than a segmented control or a row of
    /// chips, because eleven seasons do not fit across a phone and the apps
    /// that have this problem all solved it the same way.
    private var picker: some View {
        Menu {
            ForEach(seasons, id: \.self) { number in
                Button {
                    season = number
                } label: {
                    if number == shownSeason {
                        Label("Season \(number)", systemImage: "checkmark")
                    } else {
                        Text("Season \(number)")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Season \(shownSeason ?? 1)")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(SoundChexTheme.ink100)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(SoundChexTheme.base700, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityLabel("Season \(shownSeason ?? 1). Choose a season")
    }
}

/// One episode: still, number and title, duration, synopsis.
private struct EpisodeRow: View {
    let episode: MediaItem
    let progress: Double?
    let onPlay: () -> Void
    let onDownload: () -> Void

    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                HStack(alignment: .top, spacing: 12) {
                    still

                    VStack(alignment: .leading, spacing: 3) {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SoundChexTheme.ink100)
                            .multilineTextAlignment(.leading)

                        if let length = lengthLabel {
                            Text(length)
                                .font(.footnote)
                                .foregroundStyle(SoundChexTheme.ink500)
                        }
                    }

                    Spacer(minLength: 0)

                    // The download state, as a mark rather than a control:
                    // the whole row is already a button, and a button inside
                    // a button is a tap target nobody can hit reliably.
                    // Downloading is in the row's long-press menu.
                    //
                    // All of the states, not just "stored": this showed a
                    // green tick or nothing at all, so an episode downloading
                    // for several minutes looked exactly like one nobody had
                    // asked for.
                    downloadMark
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // The synopsis sits under the row at full width rather than beside
            // the still: two or three lines in a column narrowed by a 120pt
            // thumbnail wrap to a sliver, which is why the streaming apps put
            // it here too.
            if let overview = episode.meta?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.footnote)
                    .foregroundStyle(SoundChexTheme.ink400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Play", onPlay)
        .accessibilityAction(named: "Download", onDownload)
        .contextMenu {
            EpisodeActions(episode: episode) { _ in onDownload() }
        }
    }

    /// Where this episode's download has got to.
    @ViewBuilder
    private var downloadMark: some View {
        switch downloads.state(for: episode.id) {
        case .idle:
            EmptyView()

        case .queued:
            Image(systemName: "clock")
                .font(.footnote)
                .foregroundStyle(SoundChexTheme.ink500)
                .accessibilityHidden(true)

        case .downloading(let progress):
            // The same ring the shared button draws, at row scale. A floor on
            // the trim so a download that has just started is visibly
            // *something* rather than an empty circle.
            ZStack {
                Circle()
                    .stroke(SoundChexTheme.base600, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(SoundChexTheme.accent, style: .init(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

        case .stored:
            Image(systemName: "arrow.down.circle.fill")
                .font(.footnote)
                .foregroundStyle(SoundChexTheme.storedGreen)
                .accessibilityHidden(true)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
    }

    /// The still, with a play affordance and the resume bar the apps show.
    private var still: some View {
        ZStack {
            Artwork(item: episode, size: 112, aspect: 0.5625, shape: .roundedSquare(4))

            Image(systemName: "play.circle")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 3)
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .bottom) {
            // Part-watched episodes carry the same red sliver as the cards on
            // Home, so "where was I" is answerable without opening anything.
            if let progress, progress > 0.01 {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(SoundChexTheme.accent)
                        .frame(width: geometry.size.width * min(progress, 1), height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
            }
        }
    }

    /// "1. Pilot" — the number and the title as one line, the way an episode
    /// is referred to out loud.
    private var heading: String {
        let title = episode.meta?.episodeTitle ?? episode.title

        guard let number = episode.meta?.episodeNumber else { return title }

        return "\(number). \(title)"
    }

    /// "57m", or "1h 2m" for a long one.
    private var lengthLabel: String? {
        guard let minutes = episode.meta?.runtimeMinutes, minutes > 0 else { return nil }

        let hours = minutes / 60
        let rest = minutes % 60

        if hours == 0 { return "\(rest)m" }

        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// The row as one sentence, since the parts are read together.
    private var spokenLabel: String {
        var parts: [String] = []

        if let season = episode.meta?.seasonNumber {
            parts.append("Season \(season)")
        }

        if let number = episode.meta?.episodeNumber {
            parts.append("Episode \(number)")
        }

        parts.append(episode.meta?.episodeTitle ?? episode.title)

        if let length = lengthLabel {
            parts.append(length)
        }

        if let progress, progress > 0.01 {
            parts.append("\(Int(progress * 100)) percent watched")
        }

        switch downloads.state(for: episode.id) {
        case .queued: parts.append("Waiting to download")
        case .downloading(let progress): parts.append("Downloading, \(Int(progress * 100)) percent")
        case .stored: parts.append("Downloaded")
        case .failed: parts.append("Download failed")
        case .idle: break
        }

        if let overview = episode.meta?.overview, !overview.isEmpty {
            parts.append(overview)
        }

        return parts.joined(separator: ", ")
    }
}

/// The per-episode actions, in a long-press menu rather than a row of buttons
/// (S-388).
///
/// Lives beside the list that shows it; it was private to `ShowDetailView`
/// while the rows were defined there, and moved with them.
///
/// An episode is gigabytes. Putting a download control on every row of a
/// 60-episode series — or a "download this season" button above it — makes
/// filling a phone a one-tap mistake, so downloading an episode is a
/// deliberate act you have to go looking for. Video also asks how long to
/// keep it (S-404), which is what makes that choice low-stakes.
struct EpisodeActions: View {
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
