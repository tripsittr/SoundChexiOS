// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// A parsed WebVTT subtitle track (S-160).
///
/// The server serves captions as WebVTT. Rather than fight AVFoundation to merge
/// a remote, auth-headed video with an external text track (compositions and
/// streamed assets do not mix cleanly), the player parses the cues here and shows
/// the current one as its own overlay, synced to playback time. Deterministic and
/// unit-testable — which matters for a feature that can only be eyeballed on a
/// device.
struct WebVTT: Sendable {
    struct Cue: Sendable, Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    let cues: [Cue]

    /// The cue active at a given playback time, or nil between cues.
    func cue(at time: TimeInterval) -> Cue? {
        // Cues are in start order; a linear scan is fine for a film's ~1,500.
        cues.first { time >= $0.start && time < $0.end }
    }

    /// Parses WebVTT text. Tolerant: unknown blocks (NOTE, STYLE, region
    /// settings) are skipped, and a malformed cue is dropped rather than failing
    /// the whole track.
    static func parse(_ content: String) -> WebVTT {
        var cues: [Cue] = []

        // Normalise line endings, then split into blocks on blank lines.
        let normalised = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for block in normalised.components(separatedBy: "\n\n") {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }

            // A leading cue identifier (a line with no "-->" before the timing
            // line) is optional; drop it.
            if !lines[0].contains("-->"), lines.count > 1, lines[1].contains("-->") {
                lines.removeFirst()
            }

            guard let timingLine = lines.first, timingLine.contains("-->") else { continue }

            let parts = timingLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = timestamp(parts[0]),
                  let end = timestamp(parts[1]) else { continue }

            let text = lines.dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            cues.append(Cue(start: start, end: end, text: stripTags(text)))
        }

        return WebVTT(cues: cues)
    }

    /// Parses a `HH:MM:SS.mmm` or `MM:SS.mmm` timestamp (cue settings after the
    /// time, like `align:start`, are ignored).
    private static func timestamp(_ raw: String) -> TimeInterval? {
        let token = raw.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""

        let pieces = token.split(separator: ":").map(String.init)
        guard !pieces.isEmpty else { return nil }

        let seconds = Double(pieces.last!.replacingOccurrences(of: ",", with: ".")) ?? -1
        guard seconds >= 0 else { return nil }

        var total = seconds
        if pieces.count >= 2 { total += (Double(pieces[pieces.count - 2]) ?? 0) * 60 }
        if pieces.count >= 3 { total += (Double(pieces[pieces.count - 3]) ?? 0) * 3600 }
        return total
    }

    /// Removes simple inline tags (`<i>`, `<c.colorname>`, `<00:00:00.000>`) that
    /// a plain text overlay does not render.
    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
