import SwiftUI

/// The persistent download control for a track.
///
/// Shows the item's download state — not yet downloaded, downloading, or stored
/// — and stays visible (unlike the row's hover-only button on the web). The
/// download store lands in IOS-05; until then this reflects "not downloaded" and
/// starting a download is a no-op with a note, so the control exists and is
/// styled but does nothing destructive.
struct DownloadButton: View {
    let item: MediaItem
    var size: CGFloat = 22

    // Placeholder state until the download store (IOS-05) provides the real one.
    @State private var state: DownloadState = .idle

    enum DownloadState { case idle, downloading, stored, failed }

    var body: some View {
        Button {
            // Wired to the download store in IOS-05.
        } label: {
            icon
                .font(.system(size: size))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .disabled(state == .downloading)
    }

    @ViewBuilder private var icon: some View {
        switch state {
        case .idle:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(SoundChexTheme.ink300)
        case .downloading:
            ProgressView().tint(SoundChexTheme.accent)
        case .stored:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SoundChexTheme.storedGreen)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(SoundChexTheme.errorPink)
        }
    }
}
