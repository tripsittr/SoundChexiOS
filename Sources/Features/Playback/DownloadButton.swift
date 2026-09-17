// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The persistent download control for a track.
///
/// Reflects the item's real download state from the DownloadStore — not
/// downloaded, downloading (with progress), or stored — and stays visible.
/// Tapping downloads; tapping a stored item offers to remove it.
struct DownloadButton: View {
    @Environment(DownloadStore.self) private var downloads
    let item: MediaItem
    var size: CGFloat = 22

    @State private var confirmingRemove = false

    var body: some View {
        Button {
            switch downloads.state(for: item.id) {
            case .stored: confirmingRemove = true
            case .downloading: break
            default: downloads.download(item)
            }
        } label: {
            icon
                .font(.system(size: size))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .confirmationDialog("Remove download?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { downloads.remove(item.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var icon: some View {
        switch downloads.state(for: item.id) {
        case .idle:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(SoundChexTheme.ink300)
        case .downloading(let progress):
            ZStack {
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(SoundChexTheme.accent, style: .init(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
                Image(systemName: "stop.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(SoundChexTheme.ink500)
            }
        case .stored:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SoundChexTheme.storedGreen)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(SoundChexTheme.errorPink)
        }
    }
}
