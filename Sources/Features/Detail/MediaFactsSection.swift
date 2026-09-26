// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The facts and credits under a film or show (S-412).
///
/// The detail page showed artwork, a play button and episodes. Everything that
/// helps someone decide what to watch — who is in it, who made it, what it is
/// rated — was already in the database and never sent, then sent and never
/// shown.
///
/// Every row here is conditional. An item that was never enriched has none of
/// this, and a page of blank labels is worse than a short page.
struct MediaFactsSection: View {
    @Environment(Session.self) private var session

    let item: MediaItem

    @State private var cast: [APIClient.Credit] = []
    @State private var crew: [APIClient.Credit] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let tagline = item.meta?.tagline, !tagline.isEmpty {
                // Italic and set apart: a tagline is the film talking about
                // itself, not a fact about it.
                Text(tagline)
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(SoundChexTheme.ink300)
                    .padding(.horizontal, 16)
            }

            if !facts.isEmpty {
                factGrid
            }

            if !cast.isEmpty {
                creditRail("Cast", cast)
            }

            if !crew.isEmpty {
                creditRail("Crew", crew)
            }
        }
        .task {
            // Once per appearance, and only for the types that have credits.
            guard !loaded, item.type == .movie || item.type == .show else { return }

            loaded = true

            guard let api = session.api,
                  let result = try? await api.details(itemID: item.id)
            else { return }

            cast = result.cast
            crew = result.crew
        }
    }

    /// The short facts, as label/value pairs. Assembled rather than written
    /// out so the ones that are absent simply do not appear.
    private var facts: [(String, String)] {
        guard let meta = item.meta else { return [] }

        var rows: [(String, String)] = []

        if let year = meta.releaseYear { rows.append(("Year", String(year))) }
        if let runtime = meta.runtimeMinutes { rows.append(("Runtime", "\(runtime) min")) }
        if let rating = meta.mpaaRating ?? meta.contentRating { rows.append(("Rated", rating)) }
        if let director = meta.director { rows.append(("Director", director)) }
        if let creator = meta.creator { rows.append(("Created by", creator)) }
        if let studio = meta.studio { rows.append(("Studio", studio)) }
        if let network = meta.network { rows.append(("Network", network)) }

        // Seasons and episodes read as one fact, not two.
        if let seasons = meta.seasonCount {
            let episodes = meta.episodeCount.map { ", \($0) episodes" } ?? ""
            rows.append(("Seasons", "\(seasons)\(episodes)"))
        }

        if let status = meta.status { rows.append(("Status", status.capitalized)) }

        // Scores side by side where both exist — they disagree often enough
        // that showing one alone is misleading.
        if let imdb = meta.imdbRating { rows.append(("IMDb", String(format: "%.1f", imdb))) }
        if let rt = meta.rtScore { rows.append(("Rotten Tomatoes", "\(rt)%")) }

        if let language = meta.language { rows.append(("Language", language.uppercased())) }
        if let country = meta.country { rows.append(("Country", country.uppercased())) }

        return rows
    }

    private var factGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { pair in
                HStack(alignment: .firstTextBaseline) {
                    Text(pair.element.0)
                        .font(.caption)
                        .foregroundStyle(SoundChexTheme.ink500)
                        .frame(width: 120, alignment: .leading)

                    Text(pair.element.1)
                        .font(.subheadline)
                        .foregroundStyle(SoundChexTheme.ink100)

                    Spacer()
                }
                .padding(.vertical, 7)

                if pair.offset < facts.count - 1 {
                    Divider().overlay(SoundChexTheme.base700)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Cast or crew as a horizontal rail of faces.
    ///
    /// Faces rather than a list because a cast is scanned for someone you
    /// recognise, not read top to bottom.
    private func creditRail(_ title: String, _ people: [APIClient.Credit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SoundChexTheme.ink100)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(people) { person in
                        VStack(spacing: 6) {
                            CachedImage(url: person.headshot) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700.overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(SoundChexTheme.ink600))
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(.circle)

                            Text(person.name)
                                .font(.caption)
                                .foregroundStyle(SoundChexTheme.ink200)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            // The character, or the job for crew — the thing
                            // that explains why this face is on this page.
                            if let detail = person.character ?? person.role?.replacingOccurrences(of: "_", with: " ").capitalized {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(SoundChexTheme.ink500)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 84)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
