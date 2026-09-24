// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Network
import Observation

/// Whether this device currently has a network at all (S-362).
///
/// Distinct from `ServerReachability`, which races candidate addresses once at
/// launch to pick the fastest. This is the standing answer to a different
/// question: can anything be fetched right now? Views ask it to decide whether
/// a track that is not downloaded can be played, so a row that cannot play is
/// shown as such rather than accepting a tap and failing silently.
///
/// Deliberately conservative. `NWPathMonitor` reports the *interface*, not
/// whether this particular server answers — a phone on hotel wifi with no
/// route to a home tailnet reads as online here. Being wrong in that direction
/// costs a failed tap and an error; being wrong the other way would grey out a
/// library that works.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    /// Whether a network interface is available. Starts true so nothing is
    /// greyed out during the moment before the first path update arrives.
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "app.soundchex.ios.connectivity")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied

            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }

                self.isOnline = online
                AppLog.info("Network \(online ? "available" : "unavailable")", category: "net")
            }
        }

        monitor.start(queue: queue)
    }
}
