// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Network
import Observation

/// Whether the *server* can be reached right now (S-362, S-415).
///
/// The question views actually need answering is not "is there wifi" but "can
/// I fetch a track". Those differ constantly here: this app talks to a server
/// the person runs themselves, usually on a home network or a tailnet, so a
/// phone on mobile data or someone else's wifi has a perfectly good internet
/// connection and no route to the library at all.
///
/// This used to wrap `NWPathMonitor` alone, which reports the *interface*.
/// Its own comment admitted the flaw — "a phone on hotel wifi with no route to
/// a home tailnet reads as online here" — and that is the common case, not an
/// edge one: nothing greyed out, every undownloaded row accepted a tap, and
/// each one failed.
///
/// So the interface is now only the trigger. The answer comes from asking the
/// server whether it is there.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    /// Whether the server answered the last time we asked.
    ///
    /// Starts true so nothing is greyed out in the moment before the first
    /// probe returns. Being briefly wrong this way costs a failed tap; being
    /// wrong the other way would grey out a working library on launch.
    private(set) var isOnline = true

    /// Where to probe. Set by `Session` once the server address is known —
    /// without it there is nothing to ask, and the app stays optimistic.
    @ObservationIgnored private var serverURL: URL?

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "app.soundchex.ios.connectivity")
    @ObservationIgnored private var probe: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // No interface at all is a definite no, with nothing to ask.
                guard path.status == .satisfied else {
                    self.set(false, because: "no network interface")
                    return
                }

                // An interface appeared or changed — which says nothing about
                // whether the server is on the other side of it.
                self.refresh()
            }
        }

        monitor.start(queue: queue)
    }

    /// Points the probe at a server. Called when the address is restored or
    /// changed, and re-checks immediately.
    func track(serverURL: URL?) {
        self.serverURL = serverURL
        refresh()
    }

    /// Re-asks the server whether it is there.
    ///
    /// Callers: a path change, a restored session, the app coming forward, and
    /// a request that failed — that last one is the most reliable signal there
    /// is, because it is the real thing failing rather than a probe.
    func refresh() {
        guard let serverURL else {
            // Nothing configured yet. Stay optimistic rather than greying out
            // a library during sign-in.
            set(true, because: "no server configured")
            return
        }

        probe?.cancel()
        probe = Task { [weak self] in
            let up = await ServerReachability.isUp(serverURL)

            guard !Task.isCancelled else { return }

            await MainActor.run { self?.set(up, because: up ? "server answered" : "server did not answer") }
        }
    }

    /// Records a failed request as evidence the server is gone.
    ///
    /// Cheaper and more truthful than waiting for the next probe: the app just
    /// tried the real thing and it did not work.
    func noteRequestFailed() {
        guard isOnline else { return }

        refresh()
    }

    private func set(_ online: Bool, because reason: String) {
        guard isOnline != online else { return }

        isOnline = online
        AppLog.info("Server \(online ? "reachable" : "unreachable") — \(reason)", category: "net")
    }
}
