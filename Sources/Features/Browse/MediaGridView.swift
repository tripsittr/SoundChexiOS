// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A poster grid — for films, shows and books, where the cover is the content.
struct MediaGridView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LibraryStore.self) private var store
    let type: MediaType
    let title: String

    /// Wider tiles where there is room, rather than more tiny ones (S-408).
    private var columns: [GridItem] {
        AdaptiveGrid.columns(minimum: 110, spacing: 14, for: horizontalSizeClass)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader()
                Group {
                    if store.isLoading && store.items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = store.loadError, store.items.isEmpty {
                        ContentUnavailableView("Couldn't load", systemImage: "wifi.slash", description: Text(error))
                    } else {
                        ScrollView {
                            // The page name as a section heading — the header bar
                            // above carries search + account, not a title.
                            Text(title)
                                .font(.title2.bold()).foregroundStyle(SoundChexTheme.ink100)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.top, 4)

                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(store.topLevel(of: type)) { item in
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

/// A poster tile: cover over a title and subtitle.
struct Poster: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(item: item, size: 110, aspect: item.type == .music ? 1 : 1.5)
                .frame(maxWidth: .infinity)
            // .caption is 12pt — too small for the primary label on a tile,
            // and it was reading as fine print next to the artwork. The title
            // of the thing is subheadline; the subtitle stays a size below it.
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(SoundChexTheme.ink100)
                .scalableTitle(limit: 2)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SoundChexTheme.ink500)
                    .lineLimit(1)
            }
        }
    }
}
