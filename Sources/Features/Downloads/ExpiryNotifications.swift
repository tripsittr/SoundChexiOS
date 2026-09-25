// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import UserNotifications

/// Warns before a timed download is removed (S-405).
///
/// ## Why local notifications and not a background task
///
/// iOS delivers a *scheduled local notification* at the time you asked for,
/// whether or not the app is running, with no background entitlement and no
/// server involved. That is a promise the platform keeps.
///
/// What it does not promise is background *execution*. `BGAppRefreshTask` runs
/// when iOS feels like it — often not for days on a phone in Low Power Mode or
/// one that rarely opens the app. So the warning is scheduled ahead of time and
/// the actual deletion stays on the sweep that runs when the app opens
/// (`DownloadStore.sweepExpiredDownloads`).
///
/// That split is why the copy says the download *will be* removed rather than
/// that it *was*. On a device that has not run the sweep, the file is still
/// there, and a notification claiming otherwise would be wrong.
@MainActor
enum ExpiryNotifications {
    /// One notification per download, keyed so it can be cancelled when the
    /// item is watched, extended or removed.
    private static func identifier(for itemID: Int) -> String {
        "download-expiry-\(itemID)"
    }

    /// How long before expiry to warn.
    ///
    /// A day's notice suits a week or three days. It does not suit a 24-hour
    /// download: the warning would fire the instant you tapped download, which
    /// is noise rather than notice. So short windows warn proportionally —
    /// still enough time to do something, never immediate.
    static func warningLead(forWindow window: TimeInterval) -> TimeInterval {
        let day: TimeInterval = 24 * 3600

        return window > day ? day : window / 6
    }

    /// Asks for permission, returning whether it was granted.
    ///
    /// Called when someone first chooses a timed download, not at launch. A
    /// permission prompt on first run — before the app has shown what it is
    /// for — is the one people deny, and a denial is hard to undo.
    static func requestPermission() async -> Bool {
        let centre = UNUserNotificationCenter.current()

        let settings = await centre.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            // Asking again does nothing — iOS shows no prompt after a denial.
            return false
        case .notDetermined:
            return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    /// Schedules the warning for one download, replacing any existing one.
    ///
    /// Nothing is scheduled when the lead time has already passed — a download
    /// with under four hours left gets no warning rather than one that fires
    /// immediately, which would arrive as the person was still looking at the
    /// screen they started it from.
    static func schedule(itemID: Int, title: String, expiresAt: Date, window: TimeInterval) {
        cancel(for: itemID)

        let lead = warningLead(forWindow: window)
        let fireAt = expiresAt.addingTimeInterval(-lead)
        let delay = fireAt.timeIntervalSinceNow

        guard delay > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        // "will be removed", not "was removed": the file is deleted by the
        // sweep when the app next opens, so on this device it is still there.
        content.body = "Downloaded copy will be removed \(phrase(for: lead)). Open it to keep it."
        content.sound = .default
        content.userInfo = ["itemID": itemID, "destination": "downloads"]

        let request = UNNotificationRequest(
            identifier: identifier(for: itemID),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false),
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Drops the warning for an item — watched, extended, removed, or already
    /// expired. An alert about a download that is no longer going anywhere is
    /// how people learn to ignore alerts.
    static func cancel(for itemID: Int) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: itemID)])
    }

    /// Clears every pending warning. For sign-out: the next person's phone
    /// should not announce the last person's downloads.
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// "in a day", "in 4 hours" — the lead time, in words someone reads once.
    private static func phrase(for lead: TimeInterval) -> String {
        let hours = Int(lead / 3600)

        if hours >= 24 { return "tomorrow" }
        if hours >= 1 { return "in \(hours) hour\(hours == 1 ? "" : "s")" }

        return "shortly"
    }
}
