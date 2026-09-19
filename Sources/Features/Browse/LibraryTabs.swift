// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

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
    @Environment(ThemeStore.self) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = LibraryStore()

    var body: some View {
        // Each tab insets its own content for the now-playing bar, so the bar
        // sits *above* the system tab bar rather than being drawn over it — an
        // inset on the TabView itself overlapped the tab bar.
        // The Search tab is gone: search lives in the persistent header (AppHeader)
        // on every page instead, alongside the account button.
        // Icons match the web media UI (SoundChexIcons) rather than SF Symbols,
        // so the native app reads as the same product and not as Apple Music.
        TabView {
            HomeView().nowPlayingInset()
                .tabItem { Label { Text("Home") } icon: { SoundChexIcons.tabImage(SoundChexIcons.Home()) } }
            MusicView().nowPlayingInset()
                .tabItem { Label { Text("Music") } icon: { SoundChexIcons.tabImage(SoundChexIcons.Music()) } }
            MediaGridView(type: .movie, title: "Movies").nowPlayingInset()
                .tabItem { Label { Text("Movies") } icon: { SoundChexIcons.tabImage(SoundChexIcons.Watch()) } }
            MediaGridView(type: .show, title: "Shows").nowPlayingInset()
                .tabItem { Label { Text("Shows") } icon: { SoundChexIcons.tabImage(SoundChexIcons.Watch()) } }
            MediaGridView(type: .book, title: "Books").nowPlayingInset()
                .tabItem { Label { Text("Books") } icon: { SoundChexIcons.tabImage(SoundChexIcons.Book()) } }
        }
        .environment(store)
        .tint(theme.accent)
        .task {
            store.attach(api: session.api)
            playback.attach(api: session.api)
            downloads.attach(api: session.api)
            await session.refreshIdentity()
            await store.loadIfNeeded()
        }
        // Coming back to the app syncs the library, so changes made on the
        // server while it was backgrounded (a duplicate merge, new imports)
        // show without a manual pull-to-refresh or a cold relaunch.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
        }
    }
}

extension View {
    /// Docks the now-playing bar above this tab's content (and thus above the
    /// system tab bar), present only while something is playing.
    func nowPlayingInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBar() }
    }

}
