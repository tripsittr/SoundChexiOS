// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Films and television behind one tab, the way the web app arranges them
/// (S-449).
///
/// The phone had five tabs — Home, Music, Movies, Shows, Books — where the
/// media centre has four, because Movies and Shows are one **Watch** entry
/// there. The web states the reason in its own nav:
///
/// > Movies and shows share one entry: choosing what to watch rarely starts
/// > with deciding between a film and an episode. The split lives as a
/// > sub-nav on that page instead.
///
/// So: one tab, with the split as a chip row at the top — the same
/// `FilterChipRow` the Music landing uses, so the two sub-navs are one control
/// rather than two that merely resemble each other.
///
/// It also buys back a tab. Five is the most iOS shows before it folds the
/// rest into "More", so the fifth was one addition away from being hidden.
struct WatchView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LibraryStore.self) private var store

    /// Which kind is showing. `nil` means both, as `FilterChipRow` intends.
    @State private var section: Section?

    enum Section: String, CaseIterable, Hashable {
        case movies = "Movies"
        case shows = "Shows"
    }

    /// Wider tiles where there is room, rather than more tiny ones (S-408).
    private var columns: [GridItem] {
        AdaptiveGrid.columns(minimum: 110, spacing: 14, for: horizontalSizeClass)
    }

    /// What the grid shows. `topLevel` rather than every item, or a show's
    /// episodes would appear beside the show itself.
    private var items: [MediaItem] {
        switch section {
        case .movies: store.topLevel(of: .movie)
        case .shows: store.topLevel(of: .show)
        case nil: store.topLevel(of: .movie) + store.topLevel(of: .show)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader()

                Group {
                    if store.isLoading && store.items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = store.loadError, store.items.isEmpty {
                        ContentUnavailableView("Couldn't load", systemImage: "wifi.slash",
                                               description: Text(error))
                    } else {
                        ScrollView {
                            // The page name as a section heading — the header
                            // bar above carries search and the account, not a
                            // title.
                            Text("Watch")
                                .font(.title2.bold()).foregroundStyle(SoundChexTheme.ink100)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.top, 4)

                            FilterChipRow(options: Section.allCases, selection: $section) {
                                $0.rawValue
                            }

                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(items) { item in
                                    NavigationLink {
                                        ShowDetailView(item: item)
                                    } label: {
                                        Poster(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(16)
                        }
                        .refreshable { await store.load() }
                    }
                }
            }
            .background(SoundChexTheme.base900)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
