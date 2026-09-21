// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// The app's version and its release name, in one place so every surface shows
/// the same thing. SoundChex uses SemVer with a music-themed name per minor
/// release — see Plans/Versioning.md — and the user wants the name shown with
/// the number everywhere it appears.
enum AppRelease {
    /// The minor → name map. A new minor adds a row here (and to Versioning.md).
    private static let names: [String: String] = [
        "0.2": "Overture",
        "0.3": "Crescendo",
        "0.4": "Interlude",
        "0.5": "Bridge",
        "0.6": "Refrain",
        "0.7": "Cadence",
        "0.8": "Reprise",
        "1.0": "Encore",
    ]

    /// The bare SemVer, e.g. "0.2.0".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The build number, e.g. "2".
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// The release name for the current version, or nil for an un-named minor.
    static var name: String? {
        name(for: version)
    }

    /// The name for a full version string like "0.2.1" — keyed on its minor.
    static func name(for version: String) -> String? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return names["\(parts[0]).\(parts[1])"]
    }

    /// Version with its name: `0.2.0 “Overture”`. The everywhere form.
    static var display: String {
        if let name { return "\(version) “\(name)”" }
        return version
    }

    /// The same, plus the build number: `0.2.0 “Overture” (2)`. Diagnostics only
    /// — the user-facing Settings shows `display` without the build number.
    static var displayWithBuild: String {
        "\(display) (\(build))"
    }
}
