// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// "Most compatible" or "Original", before a download that could be either.
///
/// A confirmation dialog rather than a sheet: two choices and one line each
/// does not earn a screen, and this already follows the retention question on
/// a video. Two full-size sheets to save one film is how a feature becomes
/// something people avoid.
///
/// Shown **only where the answer is not obvious** — a file this device cannot
/// open, which the server can also provide converted. An MP4 that plays
/// everywhere is downloaded without a word.
struct DownloadVariantPicker: ViewModifier {
    @Binding var item: MediaItem?
    let onPick: (MediaItem, DownloadVariant) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Download which copy?",
            isPresented: .init(
                get: { item != nil },
                set: { if !$0 { item = nil } },
            ),
            titleVisibility: .visible,
        ) {
            if let target = item {
                // Compatible first: it is the right answer for most people on
                // a phone, and the first button is the one a hurried tap gets.
                Button(DownloadVariant.compatible.label) {
                    onPick(target, .compatible)
                    item = nil
                }

                Button(DownloadVariant.original.label) {
                    onPick(target, .original)
                    item = nil
                }

                Button("Cancel", role: .cancel) { item = nil }
            }
        } message: {
            Text("The original will not play on this device.")
        }
    }
}

extension View {
    /// Asks which copy to download, when the two differ.
    func downloadVariantPicker(
        for item: Binding<MediaItem?>,
        onPick: @escaping (MediaItem, DownloadVariant) -> Void,
    ) -> some View {
        modifier(DownloadVariantPicker(item: item, onPick: onPick))
    }
}
