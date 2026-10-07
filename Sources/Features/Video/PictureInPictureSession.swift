// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import AVKit
import Foundation

/// The floating window, reachable from outside the screen that started it.
///
/// Picture in Picture deliberately outlives the player view, which means
/// nothing inside that view can answer two questions the rest of the app
/// needs to ask: *is a window up right now*, and *stop it, something else is
/// playing*.
///
/// Without that, starting a second video while one floats leaves two things
/// playing at once — the new one on screen and the old one in the window,
/// both fighting for the audio session.
@MainActor
@Observable
final class PictureInPictureSession {
    static let shared = PictureInPictureSession()

    private init() {}

    /// The controller currently showing a floating window, if any.
    ///
    /// Weak: AVKit owns the controller's lifetime and tears it down with its
    /// own view. Holding it strongly here would keep a dead controller alive
    /// and leave `isActive` lying about a window that has gone.
    private weak var controller: AVPlayerViewController?

    /// Whether a window is floating right now.
    var isActive: Bool { controller != nil }

    /// Whether the window is coming down because the viewer asked for the
    /// player back, rather than because they closed it.
    ///
    /// The player screen reads this to decide whether to dismiss itself when
    /// PiP activates. It has to live out here: the screen that asked is gone
    /// by the time the answer matters, so a flag passed into the screen is a
    /// flag nobody is holding.
    private(set) var isRestoring = false

    func began(controller: AVPlayerViewController) {
        self.controller = controller
    }

    /// The viewer tapped restore. Cleared once the new screen has appeared.
    func restoring() {
        isRestoring = true
    }

    /// Called by the restored screen once it is on, so an ordinary entry into
    /// PiP afterwards dismisses as it should.
    func restored() {
        isRestoring = false
    }

    func ended() {
        controller = nil
    }

    /// Stops the floating window, for when something else is about to play.
    ///
    /// `stopPictureInPicture()` rather than just pausing: the window has to
    /// come down, not sit there frozen over whatever starts next.
    func stopForNewPlayback() {
        guard let controller else { return }

        controller.player?.pause()

        // AVKit exposes the stop through the controller's own PiP state, and
        // dismissing the controller is what actually takes the window down.
        controller.dismiss(animated: false)

        self.controller = nil
    }
}
