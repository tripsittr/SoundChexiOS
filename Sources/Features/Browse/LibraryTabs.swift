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
    @Environment(DownloadStore.self) private var downloads
    @State private var store = LibraryStore()

    var body: some View {
        // Each tab insets its own content for the now-playing bar, so the bar
        // sits *above* the system tab bar rather than being drawn over it — an
        // inset on the TabView itself overlapped the tab bar.
        TabView {
            HomeView().nowPlayingInset()
                .tabItem { Label("Home", systemImage: "house.fill") }
            MediaListView(type: .music, title: "Music").nowPlayingInset()
                .tabItem { Label("Music", systemImage: "music.note") }
            MediaGridView(type: .movie, title: "Movies").nowPlayingInset()
                .tabItem { Label("Movies", systemImage: "film") }
            MediaGridView(type: .show, title: "Shows").nowPlayingInset()
                .tabItem { Label("Shows", systemImage: "tv") }
            MediaGridView(type: .book, title: "Books").nowPlayingInset()
                .tabItem { Label("Books", systemImage: "book") }
            SearchView().nowPlayingInset()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .environment(store)
        .tint(SoundChexTheme.accent)
        .task {
            store.attach(api: session.api)
            playback.attach(api: session.api)
            downloads.attach(api: session.api)
            await store.loadIfNeeded()
        }
    }
}

private extension View {
    /// Docks the now-playing bar above this tab's content (and thus above the
    /// system tab bar), present only while something is playing.
    func nowPlayingInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBar() }
    }
}
