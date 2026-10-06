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
            // Video is the one screen where landscape is the point, and a
            // full-screen AVPlayer already handles rotation itself. The rest
            // of the app stays portrait until its layouts are ready (S-408).
            .allowsOrientations(.allButUpsideDown)
            // The current caption, drawn over the video (S-160). AVPlayer can't
            // easily carry an external, auth-headed WebVTT track, so the line is
            // parsed and shown here, synced to the player's time.
            .overlay(alignment: .bottom) {
                if let line = subtitles.currentLine {
                    Text(line)
                        .font(ScaledFont.system(size: 18, relativeTo: .body, weight: .semibold))
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
                // On and off differ only by a filled glyph, so the state is
                // spoken. This is the control for a feature declared as
                // supported; it cannot be an unlabelled button.
                .accessibilityLabel("Subtitles")
                .accessibilityValue(subtitles.selected?.label ?? "Off")
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

        // Video should keep playing (or PiP) in the background, like audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // The player exists before the URL does.
        //
        // An `AVPlayer` with no item is valid and idle, so the controller can
        // be handed back fully formed and the item swapped in when it is
        // known. The alternative -- resolving the URL first and building the
        // player afterwards -- means the asynchronous work has to reach back
        // into `makeUIViewController`'s `context`, which is only valid for the
        // duration of that call. Capturing it in a `Task` and touching
        // `context.coordinator` after the function returned is what crashed
        // the player on every video.
        let player = AVPlayer()
        controller.player = player

        // The coordinator is attached now, while `context` is still live. It
        // observes the player rather than the item, so it does not care that
        // nothing is loaded yet.
        context.coordinator.attach(player: player, item: item, api: api, subtitles: subtitles)

        // A downloaded copy needs no decision: it is on the device precisely
        // because it plays here, so this path never waits.
        if let local = DownloadStore.shared.localURL(for: item.id) {
            // Watching resets the clock on a timed download (S-404): the
            // window means "unused for this long", so a series you are
            // part-way through does not vanish between two episodes.
            DownloadStore.shared.extendRetention(for: item.id)

            player.replaceCurrentItem(with: AVPlayerItem(asset: AVURLAsset(url: local)))
            player.play()

            return controller
        }

        // Otherwise ask the server how to play this.
        //
        // iOS cannot demux Matroska **at all**, whatever codec is inside, so
        // fetching the file and hoping -- which is what this did -- is a black
        // rectangle for every MKV in the library. The server knows the
        // container and answers with HLS where the file will not play.
        //
        // Only `player` and `api` are captured: both are references that
        // outlive this call, unlike `context`.
        Task { @MainActor [player, api] in
            let url = (try? await api.playback(itemID: item.id))?.url
                // A failed decision must not mean a blank screen. Falling back
                // to the direct stream is exactly the old behaviour: right for
                // an MP4, wrong for an MKV, and better than nothing.
                ?? api.streamURL(itemID: item.id)

            guard let url else { return }

            player.replaceCurrentItem(
                with: AVPlayerItem(asset: AVURLAsset(url: url, options: assetOptions(api: api))),
            )
            player.play()
        }

        return controller
    }

    /// The bearer header, which a remote asset needs and a local file does not.
    private func assetOptions(api: APIClient) -> [String: Any] {
        guard let token = api.token else { return [:] }

        return ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]]
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
        controller.player?.pause()
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

                guard resume > 5, let player else { return }

                // Wait for an item before seeking.
                //
                // The player is now created empty and its item swapped in once
                // the server has said how to play this, so a seek issued the
                // moment the position arrives has nothing to seek *in* and is
                // silently discarded -- the film would start from the
                // beginning, which is the one thing resuming exists to avoid.
                //
                // Polling rather than observing: this is a handful of 50ms
                // checks over the one request that is already in flight, and
                // a KVO observer here would have to be torn down on every exit
                // path for the sake of the same wait.
                for _ in 0 ..< 100 where player.currentItem == nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }

                guard player.currentItem != nil else { return }

                let time = CMTime(seconds: Double(resume), preferredTimescale: 600)

                // Completion form, to avoid the async seek overload being
                // selected inside this async task.
                player.seek(to: time, completionHandler: { _ in })
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

                // `queue: .main` puts this on the main *thread*, which is not
                // the same as being in the main *actor's* isolation domain —
                // and `MainActor.assumeIsolated` **traps** when that
                // assumption is wrong. AVFoundation does not promise which
                // domain it calls back from, so the check could fail and take
                // the app down with EXC_BREAKPOINT rather than return a wrong
                // answer (S-447).
                //
                // That is what crashed the app on opening a show: shows are
                // video, so this observer runs only for the thing that broke.
                // The same hazard is written down in OrientationLock, for the
                // same reason.
                //
                // An explicit hop asks to be on the main actor instead of
                // asserting it, which is what the status observer in
                // PlaybackController already does.
                Task { @MainActor in model.update(time: time.seconds) }
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
