// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Normalises a typed server address into a base URL.
///
/// Shared by the sign-in screen and the server-addresses screen (S-162) so both
/// interpret an address the same way: add a scheme when the user typed a bare
/// host, default to **http** for something that looks local (a LAN IP, `.local`,
/// `localhost`, or any explicit non-443 port — a plaintext dev server on :8000)
/// and **https** otherwise (a public/tunnelled hostname), and drop any path so
/// the result is a clean base to append API paths to.
enum ServerURL {
    /// The normalised base URL, or nil if the input is not a usable address.
    static func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let hasScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        let withScheme = hasScheme
            ? trimmed
            : (looksLocal(trimmed) ? "http://\(trimmed)" : "https://\(trimmed)")

        guard let components = URLComponents(string: withScheme),
              let host = components.host, !host.isEmpty else { return nil }

        var base = URLComponents()
        base.scheme = components.scheme
        base.host = host
        base.port = components.port
        return base.url
    }

    /// Whether a bare `host` or `host:port` looks like a local/dev server, which
    /// should default to plaintext http rather than https.
    static func looksLocal(_ hostPort: String) -> Bool {
        guard let c = URLComponents(string: "http://\(hostPort)"), let host = c.host else {
            return false
        }

        // An explicit port other than 443 means a dev/LAN server (443 is the one
        // port conventionally TLS).
        if let port = c.port, port != 443 {
            return true
        }

        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") {
            return true
        }

        // A private-range IPv4 literal: 10.x, 127.x, 192.168.x, 172.16–31.x.
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (192, 168):
                return true
            case (172, let b) where (16 ... 31).contains(b):
                return true
            default:
                break
            }
        }

        return false
    }
}
