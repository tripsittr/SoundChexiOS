// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Rebases a stored artwork URL onto the server the app is talking to now
/// (S-329).
///
/// The server sends absolute artwork URLs built from the address the request
/// arrived on, and a download's sidecar freezes whichever one was current when
/// the file was fetched. That address is not stable: this server answers on a
/// tailnet host, a public relay host and loopback, and only one of them works
/// from wherever the phone happens to be. A cover downloaded at home therefore
/// pointed at `…ts.net:8443`, which does not resolve away from the tailnet, and
/// the artwork simply vanished.
///
/// The path is the durable part — `/storage/artwork/…` is the same wherever the
/// server is reached — so only the host is replaced. Anything that is not on a
/// SoundChex server (an external provider's cover) is returned untouched.
enum ArtworkURL {
    /// The stored URL, pointed at `server`.
    ///
    /// Returns the original when there is no server to rebase onto, when the
    /// two already agree, or when the URL belongs to somewhere else entirely.
    static func rebased(_ url: URL, onto server: URL?) -> URL {
        guard let server,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let serverComponents = URLComponents(url: server, resolvingAgainstBaseURL: false)
        else { return url }

        // Only the server's own media is rebased. A cover hosted by a metadata
        // provider is not ours to redirect, and pointing it at this server
        // would turn a working image into a 404.
        guard isServerHosted(components) else { return url }

        components.scheme = serverComponents.scheme
        components.host = serverComponents.host
        components.port = serverComponents.port

        return components.url ?? url
    }

    /// Whether a URL looks like this product's own artwork route rather than a
    /// third party's.
    ///
    /// Matched on the path rather than the host, because the host is precisely
    /// the thing that has gone stale.
    private static func isServerHosted(_ components: URLComponents) -> Bool {
        let path = components.path

        return path.hasPrefix("/storage/artwork/")
            || path.hasPrefix("/api/v1/items/")
            || path.hasPrefix("/storage/covers/")
    }
}
