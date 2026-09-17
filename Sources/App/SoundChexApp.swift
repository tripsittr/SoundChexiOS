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
