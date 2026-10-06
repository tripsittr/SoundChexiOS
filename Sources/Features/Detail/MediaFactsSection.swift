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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: MediaItem

    @State private var overview: String?
    @State private var cast: [APIClient.Credit] = []
    @State private var crew: [APIClient.Credit] = []
    @State private var genres: [String] = []
    @State private var detail: APIClient.ItemFacts?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let tagline = item.meta?.tagline, !tagline.isEmpty {
                // Italic and set apart: a tagline is the film talking about
                // itself, not a fact about it.
                Text(tagline)
                    .font(ScaledFont.system(size: 15, relativeTo: .subheadline))
                    .italic()
                    .foregroundStyle(SoundChexTheme.ink300)
                    .padding(.horizontal, 16)
            }

            if !scores.isEmpty {
                scoreRow
            }

            if !genres.isEmpty {
                // One line, not chips: a film has two or three and a row of
                // pills would weigh more than the words are worth.
                Text(genres.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(SoundChexTheme.ink300)
                    .padding(.horizontal, 16)
            }

            // The synopsis, above the facts (S-412). It is the thing
            // someone reads to decide what to watch; a runtime and a rating
            // are what they check afterwards.
            //
            // The owner's own words when they wrote any — the server prefers
            // them over TMDB's — so this is not always a scraped blurb.
            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if !facts.isEmpty {
                factGrid
            }

            if let awards = detail?.awards, !awards.isEmpty {
                // The sentence as the source writes it -- "Nominated for 7
                // Oscars. 21 wins & 43 nominations total" -- rather than
                // parsed counts, which would invent structure it does not
                // have.
                Label(awards, systemImage: "rosette")
                    .font(.footnote)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .padding(.horizontal, 16)
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

            overview = result.overview
            cast = result.cast
            crew = result.crew
            genres = result.genres
            detail = result.facts
        }
    }

    /// The critic scores, as a source and a value.
    ///
    /// Null for everything until an OMDb key is entered: the two columns
    /// existed for a long time with nothing writing them, so an empty row here
    /// is the normal state on a fresh install rather than a failure.
    private var scores: [(String, String)] {
        guard let detail else { return [] }

        var out: [(String, String)] = []

        if let imdb = detail.imdbRating {
            // One decimal, as IMDb shows it. "8.0" reads as a score where "8"
            // reads as a count.
            out.append(("IMDb", String(format: "%.1f", imdb)))
        }

        if let rt = detail.rtScore { out.append(("Rotten Tomatoes", "\(rt)%")) }
        if let meta = detail.metascore { out.append(("Metacritic", "\(meta)")) }

        return out
    }

    /// The scores in a row, each as a small stacked pair.
    private var scoreRow: some View {
        HStack(spacing: 20) {
            ForEach(scores, id: \.0) { score in
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.1)
                        .font(ScaledFont.system(size: 17, relativeTo: .headline).weight(.semibold))
                        .foregroundStyle(SoundChexTheme.ink100)

                    Text(score.0)
                        .font(.caption2)
                        .foregroundStyle(SoundChexTheme.ink400)
                }
                // Read as one thing, not as a number and a stray word.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(score.0) \(score.1)")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
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

        // The file itself. On a server the owner runs, how big it is and when
        // it arrived are facts about the thing, not plumbing.
        if let size = detail?.fileSize, size > 0 {
            rows.append(("Size", ByteCountFormatter.string(
                fromByteCount: size, countStyle: .file)))
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
                // Label beside value normally; stacked at the accessibility
                // sizes. A 120pt label column leaves almost nothing for the
                // value once the text is three times its usual size, and a
                // director's name squeezed into a thumb's width of column is
                // not information any more.
                let label = Text(pair.element.0)
                    .font(.caption)
                    .foregroundStyle(SoundChexTheme.ink500)

                let value = Text(pair.element.1)
                    .font(.subheadline)
                    .foregroundStyle(SoundChexTheme.ink100)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            label
                            value
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            label.frame(width: 120, alignment: .leading)
                            value
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)

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
                .font(ScaledFont.system(size: 18, relativeTo: .body, weight: .semibold))
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
                            .accessibilityHidden(true)
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
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
