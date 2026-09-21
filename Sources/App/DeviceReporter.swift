// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import MetricKit
#if canImport(UIKit)
import UIKit
#endif

/// Sends crash reports and diagnostics to the server (S-293).
///
/// The old (Tauri) app reported device diagnostics to the server, surfaced in the
/// admin's Device Reports page; the native app now does the same. It:
///
///  - subscribes to **MetricKit**, Apple's sanctioned crash-diagnostic channel —
///    `MXCrashDiagnostic` payloads are delivered on the *next* launch after a
///    crash, with no third-party SDK and no fragile signal handlers;
///  - carries the recent `AppLog` buffer with every report, so the run-up to a
///    failure is visible server-side;
///  - `POST`s to `/api/v1/device-reports`, which is unauthenticated and rate
///    limited by design — a report about a broken session must not need a working
///    one.
///
/// A `MainActor` singleton so it can read the session's server address and hold
/// the MetricKit subscription for the app's lifetime.
@MainActor
final class DeviceReporter: NSObject {
    static let shared = DeviceReporter()

    /// Where to send reports. Set from the session once an address is known; a
    /// report queued before that (a crash on a cold launch) is sent when it is.
    private var serverURL: URL?
    private var pendingCrashReports: [[String: Any]] = []

    private override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    /// Point the reporter at a server. Flushes any crash captured before the
    /// address was known.
    func configure(serverURL: URL?) {
        self.serverURL = serverURL
        flushPending()
    }

    /// Sends a one-off diagnostic report — the recent log buffer, tagged with a
    /// reason. For a "something went wrong" moment or a manual "send diagnostics".
    func sendDiagnostics(reason: String) {
        let events = [logEvent(kind: "diagnostics", detail: ["reason": reason])]
        post(events: events)
    }

    // MARK: - Sending

    private func post(events: [[String: Any]]) {
        guard let serverURL else { return }

        var body: [String: Any] = [
            "device": Self.deviceIdentifier,
            "name": Self.deviceName,
            "platform": Self.platform,
            // The bare version, which fits the field; the release name rides in
            // the platform string so it is still visible in the report.
            "app_version": AppRelease.version,
            "events": events,
        ]
        // Drop nils so the JSON is clean.
        body = body.filter { !($0.value is NSNull) }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: serverURL.appendingPathComponent("api/v1/device-reports"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        // Fire and forget — a failed report must never disturb the app, and it is
        // diagnostics, not user data.
        URLSession.shared.dataTask(with: request).resume()
    }

    private func flushPending() {
        guard serverURL != nil, !pendingCrashReports.isEmpty else { return }
        let events = pendingCrashReports
        pendingCrashReports = []
        post(events: events)
    }

    /// The recent log buffer as one event carrying its lines.
    private func logEvent(kind: String, detail extra: [String: Any] = [:]) -> [String: Any] {
        let lines = AppLog.recent().map { entry in
            [
                "at": Int(entry.at.timeIntervalSince1970),
                "level": entry.level.rawValue,
                "category": entry.category,
                "message": entry.message,
            ] as [String: Any]
        }

        var detail: [String: Any] = extra
        detail["log"] = lines

        return [
            "kind": kind,
            "at": Int(Date().timeIntervalSince1970),
            "detail": detail,
        ]
    }

    // MARK: - Device identity

    /// A stable per-install id, so reports from one device group together without
    /// identifying the user. Kept in UserDefaults (survives launches, gone on
    /// reinstall — which is fine, it is only for grouping diagnostics).
    private static let deviceIdentifier: String = {
        let key = "soundchex.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = String(UUID().uuidString.prefix(40))
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    private static var platform: String {
        #if canImport(UIKit)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        return "iOS"
        #endif
    }
}

// MARK: - MetricKit

extension DeviceReporter: MXMetricManagerSubscriber {
    /// Crash (and hang/CPU-exception) diagnostics, delivered on the next launch
    /// after the event. Each becomes a `crash` event carrying the exception type,
    /// signal, termination reason and the top of the call stack — enough to place
    /// a crash without the raw `.ips`.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var events: [[String: Any]] = []

        for payload in payloads {
            for crash in payload.crashDiagnosticsBoundToLifecycle() {
                events.append(crash)
            }
        }

        guard !events.isEmpty else { return }

        // `[[String: Any]]` is not Sendable, so it cannot cross into the
        // MainActor task directly. Serialise the crash events to JSON here (a
        // Sendable Data) and rebuild them on the other side.
        guard let encoded = try? JSONSerialization.data(withJSONObject: events) else { return }

        Task { @MainActor in
            self.enqueueCrash(encoded)
        }
    }

    /// Records crash events serialised in the nonisolated MetricKit callback.
    private func enqueueCrash(_ encoded: Data) {
        guard let events = (try? JSONSerialization.jsonObject(with: encoded)) as? [[String: Any]] else { return }

        // Queue if we have no server yet (a cold-launch crash report arrives
        // before sign-in restores the address); flushed by configure().
        if serverURL == nil {
            pendingCrashReports.append(contentsOf: events)
        } else {
            post(events: events)
        }
    }
}

private extension MXDiagnosticPayload {
    /// This payload's crash diagnostics reduced to plain report events.
    func crashDiagnosticsBoundToLifecycle() -> [[String: Any]] {
        (crashDiagnostics ?? []).map { crash in
            var detail: [String: Any] = [
                "exceptionType": crash.exceptionType?.stringValue ?? "?",
                "exceptionCode": crash.exceptionCode?.stringValue ?? "?",
                "signal": crash.signal?.stringValue ?? "?",
                "terminationReason": crash.terminationReason ?? "?",
                "virtualMemoryRegionInfo": crash.virtualMemoryRegionInfo ?? "",
            ]
            if let meta = crash.metaData.dictionaryRepresentation() as? [String: Any] {
                detail["appVersion"] = meta["appVersion"]
                detail["osVersion"] = meta["osVersion"]
                detail["deviceType"] = meta["deviceType"]
            }
            // The call stack, JSON-encoded — the actual "where did it crash".
            if let stack = crash.callStackTree.jsonRepresentation() as Data?,
               let string = String(data: stack, encoding: .utf8) {
                detail["callStack"] = string
            }

            return [
                "kind": "crash",
                "at": Int(Date().timeIntervalSince1970),
                "detail": detail,
            ]
        }
    }
}
