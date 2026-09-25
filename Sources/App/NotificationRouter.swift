// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import UserNotifications

/// Where a tapped notification should take you (S-405).
///
/// Tapping an expiry warning opens Downloads, so you can see everything that
/// is going and decide — keep, remove, or watch it, which is what resets the
/// clock. The alternative, opening the one item, answers a narrower question
/// than the person is usually asking when several things expire together.
///
/// Downloads sits inside the Settings sheet rather than in the tab bar, so
/// getting there means opening a sheet *and* pushing a screen. This carries
/// that intent from the delegate, which has no view context of its own, to
/// the views that do.
@MainActor
@Observable
final class NotificationRouter: NSObject {
    /// Set when a notification asks for a screen. The view layer reads it,
    /// acts, and clears it.
    var destination: Destination?

    enum Destination: Equatable {
        case downloads
    }

    /// Installs itself as the notification delegate.
    ///
    /// Without a delegate, iOS opens the app and drops the tap on the floor —
    /// which looks like a notification that does nothing.
    func attach() {
        UNUserNotificationCenter.current().delegate = self
    }

    func clear() {
        destination = nil
    }
}

extension NotificationRouter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        let info = response.notification.request.content.userInfo
        let destination = info["destination"] as? String

        await MainActor.run {
            if destination == "downloads" {
                self.destination = .downloads
            }
        }
    }

    /// Shows the warning even while the app is open.
    ///
    /// The default is to suppress it, which would mean someone using the app
    /// when a download is about to go gets no word of it at all — the one
    /// moment they are most able to do something.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
