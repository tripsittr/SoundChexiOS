// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The admin dashboard — a read-only glance at the library and recent activity,
/// for a profile that may administer. Styled like the rest of the app.
struct AdminDashboardView: View {
    @Environment(Session.self) private var session
    @State private var stats: AdminStats?
    @State private var loading = true
    @State private var loadError: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(SoundChexTheme.accent).padding(.top, 80)
            } else if let stats {
                VStack(alignment: .leading, spacing: 24) {
                    library(stats)
                    activity(stats)
                    topItems(stats)
                }
                .padding(16)
            } else if let loadError {
                ContentUnavailableView("Couldn't load", systemImage: "chart.bar.xaxis",
                                       description: Text(loadError))
                    .padding(.top, 60)
            }
        }
        .background(SoundChexTheme.base900)
        .navigationTitle("Dashboard")
        .task { await load() }
    }

    private func library(_ s: AdminStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Library")
            LazyVGrid(columns: columns, spacing: 12) {
                statCard("Songs", s.library.music, "music.note")
                statCard("Movies", s.library.movie, "film")
                statCard("Shows", s.library.show, "tv")
                statCard("Books", s.library.book, "book")
            }
        }
    }

    private func activity(_ s: AdminStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Activity")
            LazyVGrid(columns: columns, spacing: 12) {
                statCard("Plays (7d)", s.playsLast7Days, "play.circle")
                statCard("Total items", s.library.total, "square.stack")
                statCard("Accounts", s.accounts, "person.circle")
                statCard("Profiles", s.profiles, "person.2")
            }
        }
    }

    @ViewBuilder private func topItems(_ s: AdminStats) -> some View {
        if !s.topItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Most played")
                VStack(spacing: 10) {
                    ForEach(s.topItems) { item in
                        HStack(spacing: 12) {
                            CachedImage(url: item.artwork) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700
                            }
                            .frame(width: 40, height: 40).clipShape(.rect(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                                if let subtitle = item.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(item.plays)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(SoundChexTheme.accent)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold)).tracking(1).textCase(.uppercase)
            .foregroundStyle(SoundChexTheme.ink500)
    }

    private func statCard(_ label: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(SoundChexTheme.accent)
            Text(value.formatted())
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SoundChexTheme.ink100)
            Text(label).font(.caption).foregroundStyle(SoundChexTheme.ink500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SoundChexTheme.base800, in: .rect(cornerRadius: 12))
    }

    private func load() async {
        loading = true
        do { stats = try await session.api?.adminStats() }
        catch { loadError = (error as? APIClient.APIError)?.errorDescription ?? "Could not load stats." }
        loading = false
    }
}
