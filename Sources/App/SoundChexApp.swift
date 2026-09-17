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

    init() {
        configureBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(playback)
                .preferredColorScheme(.dark)
                .tint(SoundChexTheme.accent)
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
                LibraryTabs()
            } else {
                SignInView()
            }
        }
        .task {
            await session.restore()
        }
    }
}
