// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The progress line under a "download all" button (S-394).
///
/// A batch download takes minutes. The old artist and album pages announced
/// "Downloading 40 songs…" and then cleared the message after three seconds,
/// so for the rest of those minutes the page looked idle and the only way to
/// tell it was working was to leave and come back. This keeps the line up for
/// as long as the batch runs and counts it down.
///
/// It is a value type rather than three copies of the same `@State` because
/// the playlist page had already grown its own version of this and the artist
/// and album pages were about to grow two more. The counting is subtle enough
/// — see `remaining` — that three copies would have meant three chances to get
/// it wrong.
@MainActor
struct BatchDownloadStatus {
    /// What was asked for. Emptied when the batch settles, which is what stops
    /// `message` describing a download the user has long since forgotten.
    private(set) var trackIDs: Set<Int> = []

    /// A message with no batch behind it: "already downloaded", "not enough
    /// space", or the completion note. Cleared by the next batch.
    private(set) var standaloneMessage: String?

    /// The noun for this collection, used in the completion message.
    let noun: String

    init(noun: String) {
        self.noun = noun
    }

    /// Items still to settle — neither stored nor given up on.
    ///
    /// Failures count as settled deliberately. Counting only `isStored` leaves
    /// a batch with one dead track stuck at "1 remaining" forever, which is
    /// how the playlist page behaved before this: the completion branch never
    /// fired because the count never reached zero.
    func remaining(_ downloads: DownloadStore) -> Int {
        trackIDs.filter { id in
            switch downloads.state(for: id) {
            case .stored, .failed: false
            case .idle, .queued, .downloading: true
            }
        }.count
    }

    /// How many of the batch are done, for "Downloading 12 of 40".
    func settled(_ downloads: DownloadStore) -> Int {
        trackIDs.count - remaining(downloads)
    }

    /// The line to show, or nil for nothing.
    func message(_ downloads: DownloadStore) -> String? {
        guard !trackIDs.isEmpty else { return standaloneMessage }

        let total = trackIDs.count
        let done = settled(downloads)

        return "Downloading \(done + 1) of \(total)"
    }

    /// Starts tracking a batch. Pass the ids that were actually queued — the
    /// ones already on the device are not part of the countdown.
    mutating func start(_ result: DownloadStore.BatchResult, pendingIDs: Set<Int>) {
        standaloneMessage = nil

        switch result {
        case .started:
            trackIDs = pendingIDs
        case .insufficientSpace:
            trackIDs = []
            standaloneMessage = "Not enough free space on this device"
        case .nothingToDo:
            trackIDs = []
            standaloneMessage = "Everything in this \(noun) is already downloaded"
        }
    }

    /// Called when the remaining count reaches zero. Reports failures rather
    /// than claiming success: a batch that lost tracks to a dead file or a
    /// dropped connection has not "completed", and the user is the only one
    /// who can do anything about it.
    mutating func finish(_ downloads: DownloadStore) {
        let failed = trackIDs.filter { downloads.state(for: $0) == .failed }.count
        let total = trackIDs.count

        trackIDs = []

        standaloneMessage = switch failed {
        case 0: "Downloaded \(total) song\(total == 1 ? "" : "s")"
        case total: "Download failed"
        default: "Downloaded \(total - failed) of \(total) — \(failed) failed"
        }
    }

    /// Whether a batch is in flight, for the count badge on the button.
    var isRunning: Bool { !trackIDs.isEmpty }
}

@MainActor
extension View {
    /// Wires a `BatchDownloadStatus` to the store so it counts down and settles
    /// on its own.
    ///
    /// The completion check is driven off the remaining count rather than a
    /// timer, so it fires when the last file lands however long that takes.
    func batchDownloadTracking(
        _ status: Binding<BatchDownloadStatus>,
        downloads: DownloadStore,
    ) -> some View {
        onChange(of: status.wrappedValue.remaining(downloads)) { _, remaining in
            guard remaining == 0, status.wrappedValue.isRunning else { return }
            status.wrappedValue.finish(downloads)
        }
    }
}
