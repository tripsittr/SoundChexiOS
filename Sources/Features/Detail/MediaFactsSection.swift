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

    /// Handed the capability badges and the synopsis once they load, so the
    /// header above can show them.
    ///
    /// This view already fetches the detail; a second call from the header
    /// would be the same request twice on every page. Optional, because every
    /// other caller just wants the section.
    var onFacts: ((_ capabilities: [String], _ overview: String?) -> Void)?

    /// Whether to draw the synopsis here.
    ///
    /// False where the page shows it higher up, under the play button, so it
    /// is not printed twice. The section keeps it by default because every
    /// other caller relies on it.
    var showsOverview: Bool = true

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
            if showsOverview, let overview, !overview.isEmpty {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(SoundChexTheme.ink200)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if !facts.isEmpty {
                factGrid
            }

            // Awards are in the score row above as "4 Oscars", and the full
            // sentence is a row in the fact grid. This rosette line was a
            // third copy: the page showed "1 win" in the row and "1 win & 7
            // nominations total" again a few inches below it.

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

            onFacts?(result.facts?.capabilities ?? [], result.overview)
        }
    }

    /// One score: an icon, the number, and what it is out of.
    private struct Score: Identifiable {
        let id: String
        /// An SF Symbol standing in for the service's logo.
        ///
        /// Not the real marks: IMDb's and Rotten Tomatoes' logos are
        /// trademarks with licensing terms attached, and bundling them in a
        /// shipped app is not something to do casually. A shape that reads as
        /// the right *kind* of thing -- a star for a user score, a tomato for
        /// the critics' verdict -- carries the meaning without the claim.
        let symbol: String
        let tint: Color
        let value: String
        /// The quiet line under the number: "3.2M", "critics", "metascore".
        let caption: String?
        let spoken: String
    }

    /// Every rating in one row — critic scores and awards together.
    ///
    /// They were in three places: a score row at the top, *the same* IMDb and
    /// Rotten Tomatoes numbers again as label/value pairs in the fact grid,
    /// and awards on their own further down with a rosette. Metacritic
    /// appeared only in the first. A reader comparing scores had to find them
    /// in two layouts and notice that one was missing from one of them.
    ///
    /// Nothing until an OMDb key is entered: these columns existed for a long
    /// time with nothing writing them, so an empty row is the normal state on
    /// a fresh install rather than a failure.
    private var scores: [Score] {
        guard let detail else { return [] }

        var out: [Score] = []

        if let imdb = detail.imdbRating {
            out.append(Score(
                id: "imdb",
                symbol: "star.fill",
                tint: Color(red: 0.96, green: 0.78, blue: 0.11),
                // One decimal, as IMDb shows it: "8.0" reads as a score where
                // "8" reads as a count.
                value: String(format: "%.1f", imdb),
                caption: detail.imdbVotes.map(Self.votes) ?? "IMDb",
                spoken: "IMDb \(String(format: "%.1f", imdb)) out of 10",
            ))
        }

        if let rt = detail.rtScore {
            // 60% is the line Rotten Tomatoes draws between fresh and rotten,
            // and the colour is the only part of that score most people read.
            out.append(Score(
                id: "rt",
                symbol: rt >= 60 ? "seal.fill" : "seal",
                tint: rt >= 60 ? Color(red: 0.98, green: 0.25, blue: 0.16) : SoundChexTheme.ink400,
                value: "\(rt)%",
                caption: "critics",
                spoken: "Rotten Tomatoes \(rt) percent",
            ))
        }

        if let meta = detail.metascore {
            // Metacritic's own banding: 61+ green, 40-60 yellow, below red.
            let tint: Color = switch meta {
            case 61...: Color(red: 0.0, green: 0.68, blue: 0.42)
            case 40...60: Color(red: 0.98, green: 0.80, blue: 0.21)
            default: Color(red: 0.90, green: 0.22, blue: 0.21)
            }

            out.append(Score(
                id: "metacritic",
                symbol: "m.square.fill",
                tint: tint,
                value: "\(meta)",
                caption: "metascore",
                spoken: "Metacritic \(meta) out of 100",
            ))
        }

        if let awards = detail.awards, !awards.isEmpty, let short = Self.awardSummary(awards) {
            out.append(Score(
                id: "awards",
                symbol: "rosette",
                tint: Color(red: 0.85, green: 0.72, blue: 0.40),
                value: short.value,
                caption: short.caption,
                // The full sentence is spoken even though the row shows the
                // short form: "Nominated for 7 Oscars" is the part worth
                // hearing, and VoiceOver has room for it.
                spoken: awards,
            ))
        }

        return out
    }

    /// The scores in a row, each an icon over a number.
    private var scoreRow: some View {
        // Scrolls rather than squeezing: four scores at an accessibility text
        // size do not fit across a phone, and a row that shrinks its numbers
        // to fit defeats the point of showing them.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(scores) { score in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: score.symbol)
                                .font(ScaledFont.system(size: 15, relativeTo: .subheadline))
                                .foregroundStyle(score.tint)

                            Text(score.value)
                                .font(ScaledFont.system(size: 17, relativeTo: .headline).weight(.semibold))
                                .foregroundStyle(SoundChexTheme.ink100)
                        }

                        if let caption = score.caption {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(SoundChexTheme.ink400)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(score.spoken)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// "3.2M", "179K", "847" — a vote count at a glance.
    ///
    /// The difference between a 9.2 from eleven people and a 9.2 from three
    /// million is the whole meaning of the number beside it.
    private static func votes(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            "\(count / 1_000)K"
        default:
            "\(count)"
        }
    }

    /// The headline number out of an awards sentence.
    ///
    /// OMDb writes prose — "Won 4 Oscars. 159 wins & 220 nominations total" —
    /// and the row has space for a number and a word.
    ///
    /// The **named** award wins, where the sentence names one. "4 Oscars" is
    /// the fact worth a slot in a row of scores; "159 wins" is a total that
    /// mostly counts festival prizes nobody can name, and showing it instead
    /// buries the only part a reader cares about. Falls back to the totals
    /// when no award is named, and returns nil when the sentence says nothing
    /// countable rather than inventing structure it does not have.
    ///
    /// The full sentence is still spoken, and still shown in the fact grid.
    private static func awardSummary(_ text: String) -> (value: String, caption: String)? {
        // "Won 4 Oscars", "Won 1 Primetime Emmy", "Nominated for 7 Oscars".
        //
        // The name is captured to the end of its phrase and singularised as a
        // whole. Taking the first word and stripping its "s" turned "Golden
        // Globes" into "Goldens" and dropped the "Emmy" off "Primetime Emmy",
        // which is the sort of thing that only shows up when the parser is
        // run over the real sentences.
        if let match = text.firstMatch(#"(Won|Nominated for) (\d+) ([A-Z][A-Za-z ]*[A-Za-z])"#),
           let count = Int(match.0) {
            var award = match.1.trimmingCharacters(in: .whitespaces)

            if count == 1, award.hasSuffix("s") {
                award.removeLast()
            }

            let nominated = text.lowercased().hasPrefix("nominated")

            return ("\(count)", nominated ? "\(award) nom." : award)
        }

        if let count = text.number(before: "win") {
            return ("\(count)", count == 1 ? "win" : "wins")
        }

        if let count = text.number(before: "nomination") {
            return ("\(count)", count == 1 ? "nomination" : "nominations")
        }

        if text.range(of: "Nominated", options: .caseInsensitive) != nil {
            return ("—", "nominated")
        }

        return nil
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

        // The sentence as OMDb writes it -- "Nominated for 2 Oscars. 28 wins &
        // 34 nominations total". The score row above carries the headline
        // ("2 Oscars nom."); this is the detail behind it, in the one place
        // the page keeps details.
        if let awards = detail?.awards, !awards.isEmpty {
            rows.append(("Awards", awards))
        }

        // No scores here: they are the row of icons at the top. They used to
        // appear in both places, and Metacritic in only one of them.

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

/// Two small string helpers for reading OMDb's awards prose.
private extension String {
    /// The first capture pair of a two-group pattern, trimmed.
    func firstMatch(_ pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: self,
                  range: NSRange(startIndex..., in: self),
              ),
              match.numberOfRanges >= 4,
              let number = Range(match.range(at: 2), in: self),
              let name = Range(match.range(at: 3), in: self)
        else { return nil }

        return (String(self[number]), String(self[name]))
    }

    /// The number immediately before a word: 21 in "21 wins".
    func number(before word: String) -> Int? {
        guard let range = self.range(
            of: #"(\d+) "# + NSRegularExpression.escapedPattern(for: word),
            options: .regularExpression,
        ) else { return nil }

        return Int(self[range].prefix(while: \.isNumber))
    }
}
