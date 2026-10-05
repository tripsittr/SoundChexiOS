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
    // Exists only to answer "which orientations right now" — SwiftUI has no
    // API for it, and UIApplicationDelegate is still where iOS asks (S-408).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
    // Carries a tapped notification to the screen it names (S-405).
    @State private var notifications = NotificationRouter()

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
                .environment(notifications)
                .task { notifications.attach() }
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

/// A bar for the top edge of the selected tab.
///
/// Drawn rather than shipped as an asset: it is two points of flat colour, and
/// an asset would have to be regenerated whenever the accent changes — which
/// it can, since the accent is a user setting.
///
/// The image is the full height of the tab bar with the bar at its top, and
/// `alignmentRectInsets` is not used: UIKit centres the indicator image
/// vertically, so the transparent remainder is what puts the visible part at
/// the top where the web draws it.
@MainActor
private func tabIndicator(width: CGFloat, height: CGFloat, colour: UIColor) -> UIImage {
    // 49pt is the standard tab bar height; the extra transparent space below
    // the bar is what pushes it to the top once UIKit centres the image.
    let size = CGSize(width: width, height: 49)

    return UIGraphicsImageRenderer(size: size).image { context in
        colour.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    .withRenderingMode(.alwaysOriginal)
}

/// The tab bar and nav bars painted the way the web app paints its own, so the
/// system chrome belongs to SoundChex rather than to iOS (S-449).
///
/// The shape stays Apple's — a tab bar at the bottom, a nav bar at the top, in
/// the positions and sizes iOS users already know. What changes is the finish.
/// Apple's default is a translucent material that takes its colour from
/// whatever scrolls under it; the web app uses a flat fill with a hairline
/// edge, and that is what makes the two look like one product.
///
/// Matched against `.mobile-tabs` in the media centre's stylesheet, rather
/// than approximated:
///
///     background: color-mix(in srgb, var(--color-base-800) 94%, transparent);
///     border-top: 1px solid var(--color-base-600);
///
/// The 94% is the web's own value and is kept — it is a flat fill with a
/// little of the page behind it, not a blur that samples the content.
@MainActor
private func configureBarAppearance() {
    let base800 = UIColor(SoundChexTheme.base800)
    let base900 = UIColor(SoundChexTheme.base900)
    let base600 = UIColor(SoundChexTheme.base600)

    let tab = UITabBarAppearance()
    tab.configureWithOpaqueBackground()
    tab.backgroundColor = base800.withAlphaComponent(0.94)

    // The hairline the web draws and iOS does not. `shadowColor` is the
    // separator above the bar — named for a shadow it has not been since iOS
    // 13. Without this the bar and the content behind it share an edge, which
    // is exactly the floating look the web deliberately avoids.
    tab.shadowColor = base600

    // The web marks the active tab with an accent bar along its TOP edge:
    //
    //     .mobile-tab.is-active::before { top: 0; width: 1.75rem; height: 2px }
    //
    // and says why — "the eye is already there after the icon, and an
    // underline at the bottom would sit under the home indicator". iOS marks
    // it by tinting the icon instead, so the bar is drawn here as the
    // selection indicator image: 28pt wide and 2pt tall, which is the web's
    // 1.75rem × 2px at the same scale.
    tab.selectionIndicatorImage = tabIndicator(
        width: 28, height: 2, colour: UIColor(SoundChexTheme.accent),
    )

    UITabBar.appearance().standardAppearance = tab
    UITabBar.appearance().scrollEdgeAppearance = tab

    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = base900
    nav.shadowColor = base600
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
