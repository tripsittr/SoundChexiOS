// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A poster tile matching the web `.poster`: cover art with a bottom scrim and
/// the title/subtitle over it. Used in the home rails and browse grids.
struct PosterTile: View {
    let item: MediaItem
    /// Rail width; the height follows from the type's aspect ratio.
    var width: CGFloat = 144

    private var aspect: CGFloat { item.type == .music ? 1 : 1.5 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(item: item, size: width, aspect: aspect)

            // The scrim: base-900 fading up so the title reads over any art.
            LinearGradient(
                stops: [
                    .init(color: SoundChexTheme.base900.opacity(0.95), location: 0),
                    .init(color: SoundChexTheme.base900.opacity(0.6), location: 0.35),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .bottom, endPoint: .top
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(ScaledFont.system(size: 14, relativeTo: .footnote, weight: .semibold))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .lineLimit(2)
                if let sub = subtitle {
                    Text(sub)
                        .font(ScaledFont.system(size: 12, relativeTo: .caption))
                        .foregroundStyle(SoundChexTheme.ink300)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .padding(.top, 22)
        }
        .frame(width: width, height: width * aspect)
        .overlay(alignment: .bottom) { resumeBar }
        .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
        // Spoken as one line: the parts are a single idea ("Shameless, season
        // 1 episode 9, But at Last Came a Knock"), not four labels.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// The headline: the **series** for an episode, its own title otherwise.
    ///
    /// A Continue Watching card used to read "But at Last Came a Knock" with
    /// nothing saying it was Shameless — an episode title alone identifies
    /// almost nothing. The series is the thing being watched; which episode
    /// is the detail, and it goes on the line below.
    private var headline: String {
        item.meta?.seriesTitle ?? item.title
    }

    /// "S1:E9 But at Last Came a Knock" for an episode, otherwise the web
    /// poster's "subtitle • year".
    private var subtitle: String? {
        if let episode = episodeLine { return episode }

        let parts = [item.subtitle, item.meta?.releaseYear.map(String.init)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// "S1:E9 But at Last Came a Knock", in the form the streaming apps use.
    ///
    /// Nil unless this is genuinely an episode: a series row carries no
    /// episode number, and a film carries none of this at all.
    private var episodeLine: String? {
        guard let meta = item.meta, meta.seriesTitle != nil else { return nil }

        var marker = ""

        if let season = meta.seasonNumber, let number = meta.episodeNumber {
            marker = "S\(season):E\(number)"
        } else if let number = meta.episodeNumber {
            marker = "E\(number)"
        }

        let name = meta.episodeTitle ?? item.title

        return marker.isEmpty ? name : "\(marker) \(name)"
    }

    /// How far through this the viewer is, as the red sliver along the
    /// bottom. Only where the length is known too: a fraction of an unknown
    /// duration is a guess presented as fact.
    @ViewBuilder
    private var resumeBar: some View {
        if let seconds = item.resumePosition, seconds > 0,
           let minutes = item.meta?.runtimeMinutes, minutes > 0 {
            let fraction = min(Double(seconds) / Double(minutes * 60), 1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.25))
                    Rectangle()
                        .fill(SoundChexTheme.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
    }

    /// The tile as one spoken sentence.
    private var spokenLabel: String {
        var parts: [String] = [headline]

        if let meta = item.meta, meta.seriesTitle != nil {
            if let season = meta.seasonNumber { parts.append("Season \(season)") }
            if let number = meta.episodeNumber { parts.append("Episode \(number)") }
            if let title = meta.episodeTitle { parts.append(title) }
        } else if let sub = subtitle {
            parts.append(sub)
        }

        if let seconds = item.resumePosition, seconds > 0,
           let minutes = item.meta?.runtimeMinutes, minutes > 0 {
            let left = max(0, minutes - seconds / 60)
            if left > 0 { parts.append("\(left) minutes remaining") }
        }

        return parts.joined(separator: ", ")
    }

}
