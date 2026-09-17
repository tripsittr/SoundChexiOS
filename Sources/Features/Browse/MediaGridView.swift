import SwiftUI

/// A poster grid — for films, shows and books, where the cover is the content.
struct MediaGridView: View {
    @Environment(LibraryStore.self) private var store
    let type: MediaType
    let title: String

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

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
            Text(item.title)
                .font(.caption)
                .foregroundStyle(SoundChexTheme.ink100)
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SoundChexTheme.ink500)
                    .lineLimit(1)
            }
        }
    }
}
