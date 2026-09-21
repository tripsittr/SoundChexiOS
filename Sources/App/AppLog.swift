// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import os

/// App-wide logging that also keeps a recent ring buffer for device reports
/// (S-293).
///
/// Two jobs at once: every line goes to the unified log (visible in Console and
/// on-device) *and* into a bounded in-memory buffer, so when a report is sent —
/// after a crash, or on demand — the last few hundred lines travel with it. That
/// is what makes a device-only bug diagnosable from the server rather than by
/// pulling logs off the phone by hand.
///
/// A lock-guarded singleton (not an actor) so it is callable from anywhere,
/// including non-isolated and crash-adjacent paths where an actor hop is a
/// liability. `Sendable` because every stored field is protected by the lock.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    enum Level: String, Sendable {
        case debug, info, warning, error
    }

    /// One captured line.
    struct Entry: Sendable {
        let at: Date
        let level: Level
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []
    /// Enough to see the run-up to a failure without unbounded growth.
    private let capacity = 400

    private let logger = Logger(subsystem: "app.soundchex.ios", category: "app")

    private init() {}

    // Free functions on the shared instance, plus static shorthands so call
    // sites read as `AppLog.info(...)`.
    static func debug(_ message: String, category: String = "app") { shared.log(.debug, message, category) }
    static func info(_ message: String, category: String = "app") { shared.log(.info, message, category) }
    static func warning(_ message: String, category: String = "app") { shared.log(.warning, message, category) }
    static func error(_ message: String, category: String = "app") { shared.log(.error, message, category) }

    static func recent() -> [Entry] { shared.recent() }

    private func log(_ level: Level, _ message: String, _ category: String) {
        let entry = Entry(at: Date(), level: level, category: category, message: message)

        // The unified log, so it is visible live in Console/Xcode too.
        switch level {
        case .debug: logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info: logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning: logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }

        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        lock.unlock()
    }

    /// A snapshot of the recent buffer, oldest first — for attaching to a report.
    func recent() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
