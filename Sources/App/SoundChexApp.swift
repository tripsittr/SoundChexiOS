// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The app entry point.
///
/// A single `Session` drives the whole app: it holds the server address and the
/// auth token, and decides whether to show the sign-in flow or the library. It
/// lives here at the root so every screen can reach it through the environment.
@main
struct SoundChexApp: App {
    @State private var session = Session()
    @State private var playback = PlaybackController()
    @State private var downloads = DownloadStore.shared
    @State private var theme = ThemeStore()
    // Shared, not view-local: a playlist can be created from the Add to
    // Playlist sheet on any screen, and the grid has to hear about it (S-372).
    @State private var playlists = PlaylistStore()
    // What you last played, and what you played it *from* — the Your Library
    // landing reads this (S-392).
    @State private var recents = RecentContextsStore()

    init() {
        configureBarAppearance()
        // Start the crash/diagnostics reporter at launch so its MetricKit
        // subscription is live to receive a crash captured on the *previous* run
        // (MetricKit delivers on the next launch). The server address is set once
        // restore() has it (S-293).
        _ = DeviceReporter.shared
        AppLog.info("App launched — \(AppRelease.display)", category: "lifecycle")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(playback)
                .environment(downloads)
                .environment(theme)
                .environment(playlists)
                .environment(recents)
                .environment(Connectivity.shared)
                // The user's chosen appearance and accent, applied app-wide and
                // live: changing either in Settings updates every screen at once
                // because the tint and scheme flow from the store.
                .preferredColorScheme(theme.appearance.colorScheme)
                .tint(theme.accent)
        }
    }
}

import UIKit

/// The tab bar and nav bars painted in the SoundChex dark palette, so the system
/// chrome matches the rest of the app rather than showing a translucent default.
@MainActor
private func configureBarAppearance() {
    let base800 = UIColor(SoundChexTheme.base800)
    let base900 = UIColor(SoundChexTheme.base900)

    let tab = UITabBarAppearance()
    tab.configureWithOpaqueBackground()
    tab.backgroundColor = base800.withAlphaComponent(0.94)
    UITabBar.appearance().standardAppearance = tab
    UITabBar.appearance().scrollEdgeAppearance = tab

    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = base900
    nav.titleTextAttributes = [.foregroundColor: UIColor(SoundChexTheme.ink100)]
    nav.largeTitleTextAttributes = [.foregroundColor: UIColor(SoundChexTheme.ink100)]
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav
}

/// Chooses the sign-in flow or the library, from the session's state.
private struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            if session.isSignedIn {
                // Keyed on the identity generation so a profile switch rebuilds
                // the whole signed-in tree with a fresh store against the new
                // token — the new profile has its own library and history.
                LibraryTabs()
                    .id(session.identityGeneration)
            } else {
                SignInView()
            }
        }
        .task {
            await session.restore()
            // Point the reporter at the server now that the address is known, so
            // it can send this launch's diagnostics and flush any crash captured
            // before the address was restored.
            DeviceReporter.shared.configure(serverURL: session.serverURL)
        }
    }
}
