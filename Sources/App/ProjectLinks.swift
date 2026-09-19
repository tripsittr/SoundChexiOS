// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// The project's public links, shown in Settings → About so the source, licence
/// and policies are reachable from inside the app — the same set the served web
/// app puts in its footer.
///
/// The marketing site is not on a stable public domain yet, so the legal links
/// fall back to the public GitHub repository, which is durable. Point `website`
/// at a real domain to send the legal links there instead.
enum ProjectLinks {
    /// The public repository — durable, and where the licence lives.
    static let repository = URL(string: "https://github.com/tripsittr/SoundChex")!

    /// The marketing site, once it has a stable domain. `nil` until then.
    static let website: URL? = nil

    static var source: URL { repository }

    static var licence: URL { repository.appendingPathComponent("blob/main/LICENSE") }

    static var privacy: URL { legal("server-privacy") }

    static var terms: URL { legal("server-terms") }

    static var credits: URL { docs("credits") }

    private static func legal(_ slug: String) -> URL {
        website?.appendingPathComponent("legal/\(slug)") ?? repository
    }

    private static func docs(_ slug: String) -> URL {
        website?.appendingPathComponent("docs/\(slug)") ?? repository
    }
}
