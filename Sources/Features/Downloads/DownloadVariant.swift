// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Which copy of a file to download.
///
/// Only ever asked where the two genuinely differ — a film whose container
/// this device cannot open, and which the server has a converted copy of.
/// Asking about an MP4 that plays everywhere would be a question with one
/// right answer, which is a tax on every tap.
enum DownloadVariant: String, CaseIterable, Identifiable, Sendable {
    /// The converted copy: H.264 in MP4, which plays on anything.
    case compatible
    /// The file as it sits on the server, with its full bitrate and its other
    /// audio and subtitle tracks.
    case original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compatible: "Most compatible"
        case .original: "Original"
        }
    }

    /// One short line. Long enough to make the trade clear, short enough that
    /// nobody skips it.
    var hint: String {
        switch self {
        case .compatible: "Plays on this device"
        case .original: "Full quality, may not play here"
        }
    }

    var symbol: String {
        switch self {
        case .compatible: "checkmark.circle"
        case .original: "film"
        }
    }
}
