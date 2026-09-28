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
    /// The app-wide default.
    ///
    /// **iPad rotates; iPhone does not** (S-408, stage 1).
    ///
    /// An iPad held sideways and refusing to rotate reads as a broken app
    /// rather than a deliberate choice — it is the orientation a keyboard
    /// case puts it in, and Apple's own guidance is that an iPad app should
    /// support all four. The library grids, rails and player now size
    /// themselves from the width they are given, so landscape is a wider
    /// layout rather than a stretched one.
    ///
    /// iPhone stays portrait. Landscape on a phone is still a compact width,
    /// so it gains nothing and the screens have not been designed for a
    /// short, wide frame.
    ///
    /// The reader is portrait on both, by the owner's decision: a book is
    /// read in portrait, and `BookPaginator` is single-column and
    /// size-driven, so a wider page means fewer lines and more page turns.
    static let deviceDefault: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    /// What the app permits right now. Read by `AppDelegate`, which is the
    /// only thing iOS asks.
    static var supported: UIInterfaceOrientationMask = OrientationLock.deviceDefault {
        didSet {
            AppDelegate.current = supported

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

/// Lets one screen change the orientations while it is on screen.
///
/// Two screens use it, in opposite directions: the video player widens to
/// landscape, which is the point of a film; the reader narrows to portrait,
/// because a book is read in portrait and a wider page means fewer lines per
/// turn (S-408).
struct AllowsOrientations: ViewModifier {
    let orientations: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear { OrientationLock.supported = orientations }
            // Back to the app-wide default on the way out, or leaving the
            // video player would leave the whole app rotatable — and on iPad
            // that default is all four, not portrait.
            .onDisappear { OrientationLock.supported = OrientationLock.deviceDefault }
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
    /// The orientations iOS should honour right now.
    ///
    /// Mirrored into a plain `nonisolated` box rather than read from
    /// `OrientationLock` directly. iOS does not promise to ask this on the
    /// main actor, and `MainActor.assumeIsolated` *traps* when that
    /// assumption is wrong — a crash at launch rather than a wrong answer.
    nonisolated(unsafe) static var current: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?,
    ) -> UIInterfaceOrientationMask {
        Self.current
    }
}
