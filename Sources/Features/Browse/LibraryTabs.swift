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
    @Environment(Connectivity.self) private var connectivity
    @Environment(ThemeStore.self) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NotificationRouter.self) private var notifications

    /// Opened when an expiry warning is tapped (S-405). Presented here rather
    /// than from AppHeader, which renders once per tab — five of them would
    /// race to open the same sheet.
    @State private var showingDownloads = false
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
        .onChange(of: notifications.destination) { _, destination in
            guard destination == .downloads else { return }

            showingDownloads = true
            notifications.clear()
        }
        .sheet(isPresented: $showingDownloads) {
            NavigationStack {
                DownloadsView()
            }
            .soundchexTheme(theme)
        }
        .task {
            store.attach(api: session.api)
            playback.attach(api: session.api)
            downloads.attach(api: session.api)

            // Timed downloads that ran out while the app was closed (S-404).
            // Before the library loads, so Downloads never shows a file that
            // is about to be swept a second later.
            downloads.sweepExpiredDownloads()

            // The cached catalogue first, and without waiting on anything that
            // touches the network. `refreshIdentity()` is one request with a
            // 20-second timeout, and awaiting it here meant that offline — or
            // with the server down — the library sat empty for that whole
            // timeout before the disk cache was even read, which read as "the
            // app cannot work without the server" (S-337).
            await store.loadIfNeeded()

            // Put the listener back on the track they were interrupted on,
            // paused where it stopped (S-342). Needs the catalogue, since the
            // queue is remembered as ids.
            playback.restoreRememberedState(from: store.items)

            // Admin-ness only decides whether an extra tab appears, so it can
            // settle whenever the network allows, or never.
            Task { await session.refreshIdentity() }
        }
        // Coming back to the app syncs the library, so changes made on the
        // server while it was backgrounded (a duplicate merge, new imports)
        // show without a manual pull-to-refresh or a cold relaunch.
        // Coming back online picks up whatever was still owed. A "download
        // all" started on a train stops when the signal goes and used to stay
        // stopped until the app was relaunched (S-364).
        .onChange(of: connectivity.isOnline) { _, online in
            guard online else { return }

            downloads.resumeInterrupted()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                // Leaving the foreground may be the last moment before the app
                // is killed, so write the position now rather than waiting for
                // a tick that will not come.
                playback.rememberPlaybackStateNow()
                return
            }

            // Only when it has actually gone stale: returning to the app
            // repeatedly in a minute should not re-sync each time (S-386).
            Task { await store.refreshIfStale() }

            // Anything still owed from before the app was backgrounded. The
            // background session finishes what it had already started on its
            // own; this is for what never got a slot (S-364).
            downloads.resumeInterrupted()

            // Timed downloads whose window ran out while the app was away
            // (S-404). Done on the way in rather than on a background timer:
            // iOS would not honour one reliably, and a file deleted while
            // nobody is looking is a file nobody was told about.
            downloads.sweepExpiredDownloads()
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
