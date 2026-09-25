// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI
import UIKit

/// What the app will actually rotate to, screen by screen (S-408).
///
/// `Info.plist` declares all four orientations because Apple requires it: an
/// iPad build naming only portrait is *rejected at upload*, not merely warned
/// about. But declaring an orientation is not the same as being ready for it,
/// and the layouts here have no landscape handling — no size classes, no iPad
/// variants, 36 fixed widths. Rotating into that would show testers a visibly
/// broken app.
///
/// So the plist says what the app is *allowed* to do and this says what it
/// *currently* does. As each screen learns landscape (S-408 stages), it opts
/// in here and the lock shrinks. When the last one lands this type can go.
///
/// The video player is the exception that already works: it is a
/// full-screen AVPlayer, which handles rotation itself.
@MainActor
enum OrientationLock {
    /// What the app permits right now. Read by `AppDelegate`, which is the
    /// only thing iOS asks.
    static var supported: UIInterfaceOrientationMask = .portrait {
        didSet {
            guard supported != oldValue else { return }

            // Ask the window to re-evaluate. Without this the change takes
            // effect only at the next rotation the user happens to make,
            // which reads as the setting not working.
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }

            scene.requestGeometryUpdate(.iOS(interfaceOrientations: supported))
        }
    }
}

/// Lets one screen widen the orientations while it is on screen.
///
/// Applied to the video player, which is the one place landscape is the point
/// rather than an accident.
struct AllowsOrientations: ViewModifier {
    let orientations: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear { OrientationLock.supported = orientations }
            // Back to the app-wide default on the way out, or leaving the
            // video player would leave the whole app rotatable.
            .onDisappear { OrientationLock.supported = .portrait }
    }
}

extension View {
    /// Permits these orientations while this view is on screen (S-408).
    func allowsOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        modifier(AllowsOrientations(orientations: orientations))
    }
}

/// The delegate exists only to answer the orientation question.
///
/// SwiftUI has no API for "which orientations does this app support right
/// now" — `UIApplicationDelegate` is still the only place iOS asks.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?,
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.supported }
    }
}
