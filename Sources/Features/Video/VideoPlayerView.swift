import SwiftUI
import AVKit

/// A full video player for films and episodes.
///
/// Wraps `AVPlayerViewController`, which brings the standard transport,
/// fullscreen, AirPlay and — with `allowsPictureInPicturePlayback` — Picture in
/// Picture for free. The stream is the token-authed video route, with the bearer
/// token on the asset (same as audio); a downloaded copy plays from disk. Video
/// pauses the audio player first so the two are never fighting for the session.
struct VideoPlayerView: View {
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    var body: some View {
        VideoPlayerContainer(item: item, api: session.api)
            .ignoresSafeArea()
            .background(.black)
            .onAppear {
                // Video takes over audio: stop the music player so the two don't
                // both hold the audio session.
                if playback.isPlaying { playback.togglePlayPause() }
            }
    }
}

/// UIKit bridge: an AVPlayerViewController configured for PiP, resuming from the
/// server's saved position and reporting progress back as it plays.
private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let item: MediaItem
    let api: APIClient?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect

        guard let api else { return controller }

        let player = AVPlayer(playerItem: makeItem(api: api))
        controller.player = player

        // Video should keep playing (or PiP) in the background, like audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        context.coordinator.attach(player: player, item: item, api: api)
        player.play()

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
        controller.player?.pause()
    }

    /// The asset for the item — the local file when downloaded, else the
    /// token-authed stream with the bearer header.
    private func makeItem(api: APIClient) -> AVPlayerItem {
        if let local = DownloadStore.shared.localURL(for: item.id) {
            return AVPlayerItem(asset: AVURLAsset(url: local))
        }
        var options: [String: Any] = [:]
        if let token = api.token {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": "Bearer \(token)"]
        }
        let url = api.streamURL(itemID: item.id)!
        return AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    }

    /// Resumes from and reports progress to the server, off the UI.
    final class Coordinator {
        private var player: AVPlayer?
        private var timeObserver: Any?
        private var api: APIClient?
        private var itemID = 0
        private var lastReported = -1

        func attach(player: AVPlayer, item: MediaItem, api: APIClient) {
            self.player = player
            self.api = api
            self.itemID = item.id

            Task { @MainActor [weak player] in
                let resume = (try? await api.progress(itemID: item.id))?.position ?? 0
                if resume > 5, let player {
                    let time = CMTime(seconds: Double(resume), preferredTimescale: 600)
                    // Completion form, to avoid the async seek overload being
                    // selected inside this async task.
                    player.seek(to: time, completionHandler: { _ in })
                }
            }

            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main
            ) { [weak self] time in
                self?.report(seconds: time.seconds)
            }
        }

        private func report(seconds: Double) {
            guard seconds.isFinite else { return }
            let s = Int(seconds)
            guard s != lastReported, s > 0 else { return }
            lastReported = s
            let duration = Int(player?.currentItem?.duration.seconds ?? 0)
            let id = itemID
            let api = api
            Task { try? await api?.saveProgress(itemID: id, position: s, duration: duration) }
        }

        func stop() {
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            timeObserver = nil
        }
    }
}
