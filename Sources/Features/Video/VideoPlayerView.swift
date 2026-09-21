// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

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

    @State private var subtitles = SubtitleModel()

    var body: some View {
        VideoPlayerContainer(item: item, api: session.api, subtitles: subtitles)
            .ignoresSafeArea()
            .background(.black)
            // The current caption, drawn over the video (S-160). AVPlayer can't
            // easily carry an external, auth-headed WebVTT track, so the line is
            // parsed and shown here, synced to the player's time.
            .overlay(alignment: .bottom) {
                if let line = subtitles.currentLine {
                    Text(line)
                        .font(.system(size: 18, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 3)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: .rect(cornerRadius: 6))
                        .padding(.bottom, 60)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }
            // A caption picker, top-trailing, shown once tracks are known.
            .overlay(alignment: .topTrailing) {
                if !subtitles.tracks.isEmpty {
                    subtitleMenu
                        .padding(.top, 50).padding(.trailing, 16)
                }
            }
            .task {
                subtitles.configure(api: session.api, itemID: item.id)
                await subtitles.loadTracks()
            }
            .onAppear {
                // Video takes over audio: stop the music player so the two don't
                // both hold the audio session.
                if playback.isPlaying { playback.togglePlayPause() }
            }
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                Task { await subtitles.select(nil) }
            } label: {
                Label("Off", systemImage: subtitles.selected == nil ? "checkmark" : "")
            }
            ForEach(subtitles.tracks) { track in
                Button {
                    Task { await subtitles.select(track) }
                } label: {
                    Label(track.label, systemImage: subtitles.selected?.id == track.id ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "captions.bubble\(subtitles.selected != nil ? ".fill" : "")")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.5), in: .circle)
        }
    }
}

/// UIKit bridge: an AVPlayerViewController configured for PiP, resuming from the
/// server's saved position and reporting progress back as it plays.
private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let item: MediaItem
    let api: APIClient?
    let subtitles: SubtitleModel

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

        context.coordinator.attach(player: player, item: item, api: api, subtitles: subtitles)
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
        private var subtitleObserver: Any?
        private var api: APIClient?
        private var itemID = 0
        private var lastReported = -1
        private var subtitles: SubtitleModel?

        func attach(player: AVPlayer, item: MediaItem, api: APIClient, subtitles: SubtitleModel) {
            self.player = player
            self.api = api
            self.itemID = item.id
            self.subtitles = subtitles

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

            // A finer observer for captions — ~4×/second so a line changes on
            // time. Its own observer so the 5s progress cadence is unaffected.
            subtitleObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
            ) { [weak self] time in
                guard let model = self?.subtitles else { return }
                MainActor.assumeIsolated { model.update(time: time.seconds) }
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
            if let subtitleObserver { player?.removeTimeObserver(subtitleObserver) }
            timeObserver = nil
            subtitleObserver = nil
        }
    }
}
