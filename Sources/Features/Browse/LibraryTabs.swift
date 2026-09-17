import SwiftUI

/// The signed-in app: a tab bar over the library, plus search and settings.
///
/// The whole catalogue is loaded once into a shared `LibraryStore` and every tab
/// filters it, mirroring how the web app treats the mirror — one fetch, many
/// views. Streaming still needs the network, but browsing does not re-fetch per
/// tab.
struct LibraryTabs: View {
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback
    @State private var store = LibraryStore()

    var body: some View {
        TabView {
            MediaListView(type: .music, title: "Music")
                .tabItem { Label("Music", systemImage: "music.note") }
            MediaGridView(type: .movie, title: "Movies")
                .tabItem { Label("Movies", systemImage: "film") }
            MediaGridView(type: .show, title: "Shows")
                .tabItem { Label("Shows", systemImage: "tv") }
            MediaGridView(type: .book, title: "Books")
                .tabItem { Label("Books", systemImage: "book") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .environment(store)
        // The now-playing bar rides above the tab bar, present on every tab.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NowPlayingBar()
        }
        .task {
            store.attach(api: session.api)
            playback.attach(api: session.api)
            await store.loadIfNeeded()
        }
    }
}
