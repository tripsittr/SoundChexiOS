import SwiftUI

/// Search across the loaded library.
///
/// For now it filters the local catalogue, which covers titles, artists, albums
/// and authors instantly with no round trip. A server search endpoint (which also
/// searches dialogue and book text) is a later addition; when it lands this
/// screen queries it and falls back to the local filter offline.
struct SearchView: View {
    @Environment(LibraryStore.self) private var store
    @State private var term = ""

    var body: some View {
        NavigationStack {
            List(store.search(term)) { item in
                HStack(spacing: 12) {
                    Artwork(item: item, size: 44, aspect: item.type == .music ? 1 : 1.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
                        }
                    }
                }
                .listRowBackground(SoundChexTheme.base900)
            }
            .listStyle(.plain)
            .overlay {
                if term.count < 2 {
                    ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
                } else if store.search(term).isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            }
            .navigationTitle("Search")
            .background(SoundChexTheme.base900)
        }
        .searchable(text: $term, prompt: "Songs, films, books…")
    }
}
