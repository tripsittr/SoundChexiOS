// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Picks the fastest reachable address for a server (S-162).
///
/// The same SoundChex server can be reachable at more than one address — a fast
/// LAN address (`http://192.168.1.10:8000`, ~20ms) and a relay/tunnel hostname
/// (`https://…ts.net`, ~700ms) that also works away from home. The web connect
/// screen raced these; the native app should too, so it uses the local path when
/// you are home and the tunnel when you are not, without you switching anything.
///
/// The race probes each candidate's `/up` (Laravel's built-in health route —
/// unauthenticated and cheap) and returns the first to answer 200, which is the
/// fastest *currently reachable* path, not merely the first in the list.
enum ServerReachability {
    /// How long to wait before giving up on all candidates. A LAN address answers
    /// in milliseconds; the tunnel in well under a second when it is up.
    private static let timeout: TimeInterval = 2.5

    /// The fastest reachable candidate, or nil if none answered in time.
    ///
    /// Candidates are probed concurrently; the first success wins and the rest are
    /// cancelled. Order in `candidates` is a tie-break only — reachability decides.
    static func fastest(among candidates: [URL]) async -> URL? {
        let unique = orderedUnique(candidates)

        guard unique.count > 1 else { return unique.first }

        return await withTaskGroup(of: URL?.self) { group in
            for url in unique {
                group.addTask { await isUp(url) ? url : nil }
            }

            for await result in group {
                if let winner = result {
                    group.cancelAll()
                    return winner
                }
            }

            return nil
        }
    }

    /// Whether a server answers its health route at this address.
    private static func isUp(_ base: URL) async -> Bool {
        let url = base.appendingPathComponent("up")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        // A stale cached 200 would make an unreachable address look reachable.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// De-duplicates while preserving order — the caller's preference order is the
    /// tie-break when two paths are equally fast.
    private static func orderedUnique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for url in urls where seen.insert(url.absoluteString).inserted {
            out.append(url)
        }
        return out
    }
}
