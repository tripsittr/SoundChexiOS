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

    /// Shows this player again after Picture in Picture is restored.
    ///
    /// The presenting view owns the `fullScreenCover`, so only it can bring
    /// the screen back -- the player cannot re-present itself.
    var onRestore: () -> Void = {}

    @State private var subtitles = SubtitleModel()

    /// Dismisses this screen the moment Picture in Picture takes the video.
    ///
    /// AVKit otherwise leaves a bare "this video is playing in Picture in
    /// Picture" placeholder behind -- no transport, no close button, and the
    /// app unreachable underneath it. That placeholder should never be on
    /// screen: either the window floats over the app, with the app usable,
    /// or it floats outside the app. There is no third state worth showing.
    private func pictureInPictureChanged(_ active: Bool) {
        guard active else { return }

        // Not while the system is handing the video *back*.
        //
        // Restoring re-presents this screen, and AVKit reports PiP as active
        // again briefly during that handover -- so dismissing unconditionally
        // closed the screen the instant it reappeared. The video paused, the
        // audio did not return, and asking for full screen took the window
        // away entirely.
        // Asked of the session rather than a flag passed into this screen:
        // the screen that requested the restore is gone by the time this
        // matters, so a passed flag is one nobody is holding -- and the value
        // SwiftUI captured when it built this cover may predate the request.
        guard !PictureInPictureSession.shared.isRestoring else { return }

        dismiss()
    }

    var body: some View {
        VideoPlayerContainer(
            item: item,
            api: session.api,
            subtitles: subtitles,
            onRestore: onRestore,
            onPictureInPictureChange: pictureInPictureChanged,
        )
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

                // The handover is over once this screen is on, so an
                // ordinary entry into PiP from here dismisses as it should.
                PictureInPictureSession.shared.restored()
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

    /// Called when PiP's restore button is tapped, so the presenting view can
    /// show the player again. Without it PiP is a one-way trip.
    let onRestore: () -> Void

    /// Reports whether a floating window currently holds the video, so the
    /// screen can offer its own way out while AVKit's chrome is gone.
    let onPictureInPictureChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect

        guard let api else { return controller }

        // Video should keep playing (or PiP) in the background, like audio.
        //
        // Set on **every** build of the player, not once per app launch, and
        // deliberately so: a player restored out of Picture in Picture is a
        // fresh controller, and the session may have been deactivated while
        // the window was up. Without re-activating here the picture came
        // back and the sound did not -- which is exactly what was reported
        // after a PiP round trip.
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
        // The coordinator answers the PiP callbacks, so dismantling can tell
        // a dismissed player from one that is still floating.
        controller.delegate = context.coordinator
        context.coordinator.onRestore = onRestore
        context.coordinator.onPictureInPictureChange = onPictureInPictureChange

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
        // Leave a Picture in Picture window alone.
        //
        // This paused unconditionally, so dismissing the player killed PiP
        // the instant the view went away -- which is the opposite of what PiP
        // is for. YouTube's behaviour, and the one people expect, is that
        // leaving the page is exactly when the floating window takes over.
        //
        // This is now also what makes the auto-dismiss safe: the screen
        // closes itself the moment PiP starts, so this runs on *every* entry
        // into Picture in Picture, and pausing here would stop the window
        // before it had shown a frame.
        //
        // The flag is tracked from the start/stop delegate callbacks.
        // `AVPlayerViewController` exposes no `isPictureInPictureActive` --
        // I assumed one and the compiler corrected me.
        if coordinator.isInPictureInPicture {
            return
        }

        coordinator.stop()
        controller.player?.pause()
    }

    /// Resumes from and reports progress to the server, off the UI.
    ///
    /// Main-actor isolated as a whole, not method by method: AVKit calls the
    /// delegate on the main thread, and the restore callback has to touch
    /// `PictureInPictureSession` **synchronously** -- the screen decides
    /// whether to dismiss itself in the very next callback, so a flag set
    /// after an `await` arrives too late and the placeholder comes back.
    ///
    /// Partial isolation is not an option: the compiler rejects a conformance
    /// that crosses into actor-isolated code in only some of its methods, and
    /// `AVPlayerViewControllerDelegate` is not itself isolated -- hence
    /// `@preconcurrency`, which is the sanctioned way to say "this framework
    /// calls me on the main thread" for a protocol predating concurrency.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        /// Whether the video is still on screen as a floating window.
        ///
        /// Asked by `dismantleUIViewController`, which otherwise pauses
        /// unconditionally and so killed Picture in Picture the moment the
        /// player screen was dismissed -- the opposite of what PiP is for.
        private(set) var isInPictureInPicture = false

        /// Asks the presenting view to show the player again.
        ///
        /// Set by the container, because only the view that presented the
        /// cover can present it a second time.
        var onRestore: (() -> Void)?

        /// Tells the screen when PiP takes the video and gives it back.
        var onPictureInPictureChange: ((Bool) -> Void)?

        /// Whether the PiP window is closing because the user asked for the
        /// player back, rather than because they dismissed it.
        private var isRestoring = false

        func playerViewControllerDidStartPictureInPicture(_ controller: AVPlayerViewController) {
            isInPictureInPicture = true
            onPictureInPictureChange?(true)

            // Registered so the rest of the app can find this window --
            // starting another video has to take it down rather than leave
            // two things playing at once.
            PictureInPictureSession.shared.began(controller: controller)
        }

        /// Puts the player screen back when PiP's restore button is tapped.
        ///
        /// **This was missing, and its absence is why PiP was a dead end
        /// inside the app.** Without it the system has nowhere to return to:
        /// the player view shows "this video is playing in Picture in
        /// Picture" and the restore button does nothing, so there is no way
        /// back and no way to close.
        ///
        /// The completion handler must be called either way. Reporting
        /// `false` leaves the system believing the restore failed, which is
        /// what leaves the placeholder on screen for ever.
        func playerViewController(
            _ controller: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void,
        ) {
            guard let onRestore else {
                // Nothing to restore to -- say so rather than claiming
                // success, so the system dismisses PiP cleanly.
                completion(false)

                return
            }

            // Remembered because `DidStopPictureInPicture` fires after a
            // restore as well as after a close, and it pauses. Without this
            // flag the restored video would come back already paused.
            isRestoring = true
            PictureInPictureSession.shared.restoring()

            onRestore()

            // The cover is driven by SwiftUI state, so the presentation
            // happens on the next runloop pass rather than synchronously.
            // Reporting success immediately is correct: the restore *will*
            // happen, and the alternative is the system tearing PiP down
            // before the screen is back.
            completion(true)
        }

        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            isInPictureInPicture = false
            onPictureInPictureChange?(false)

            PictureInPictureSession.shared.ended()

            // This fires for both endings: the restore button, and closing
            // the window. Only the second is the end of the viewing.
            if isRestoring {
                isRestoring = false

                return
            }

            // Closing the floating window is the end of the viewing, and the
            // view it belonged to is already gone -- so the observers have to
            // be released here or they outlive the player.
            stop()
            controller.player?.pause()
        }

        private var player: AVPlayer?
        private var timeObserver: Any?
        private var subtitleObserver: Any?
        private var api: APIClient?
        private var itemID = 0
        private var lastReported = -1
        private var subtitles: SubtitleModel?

        /// Watches the item for a failure, so a playback that never starts
        /// says why.
        ///
        /// Without this the player is silent when it breaks: a stream it
        /// cannot read looks exactly like one that has not buffered yet, and
        /// the screen stays black with the clock running. That is what the
        /// HLS segment bug looked like from the phone -- the playlist loaded,
        /// so the duration was right, and every segment was a redirect to a
        /// login page that AVPlayer dutifully decoded as video.
        private var statusObserver: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?

        /// Watches for the audio session being interrupted and handed back.
        ///
        /// The audio player has had this for a long time; video never did, so
        /// a pause in Picture in Picture could leave the session inactive and
        /// the resume was silent -- the picture moved, the sound did not.
        private var interruptionObserver: NSObjectProtocol?

        /// Whether video was actually playing when an interruption began.
        ///
        /// Without it, something paused before the interruption starts on its
        /// own when the interruption ends, which is worse than staying quiet.
        ///
        /// A main-actor box rather than a property on this class: the
        /// `Coordinator` is not isolated, so sending `self` into the hop is a
        /// data race the compiler rightly rejects. Only the box crosses, and
        /// it lives on the actor that reads it.
        @MainActor
        private final class ResumeFlag {
            var wasPlaying = false
        }

        @MainActor private static let resumeFlag = ResumeFlag()

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

            watchForFailure(player: player, item: item)
            watchForInterruption(player: player)

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

            // `Int(duration.seconds)` **traps** on a duration that is not a
            // number, and `?? 0` does not save it: the optional chain
            // succeeds and hands back NaN, which `Int(_:)` then crashes on.
            //
            // That is not a rare case. `CMTime.indefinite.seconds` is NaN,
            // and an HLS stream has an indefinite duration until enough of
            // the playlist has loaded to know one -- so the first progress
            // tick of a transcoded episode landed on it. It crashed the app
            // on opening exactly the episodes that transcode, while the ones
            // that direct-play (whose duration is known immediately) were
            // fine.
            //
            // `Int(exactly:)` answers nil rather than trapping, and a nil
            // duration is a perfectly good thing to send: the server already
            // treats it as unknown.
            let duration = (player?.currentItem?.duration.seconds).flatMap { Int(exactly: $0.rounded()) }

            let id = itemID
            let api = api

            Task { try? await api?.saveProgress(itemID: id, position: s, duration: duration) }
        }

        /// Re-activates the audio session when an interruption ends.
        ///
        /// Pausing in Picture in Picture, a phone call, or another app taking
        /// the session can all leave it inactive. `AVPlayer` happily resumes
        /// the *picture* without it, so the symptom is a video playing with
        /// no sound rather than an error -- and it is intermittent, because
        /// it depends on whether the system took the session away during the
        /// pause.
        ///
        /// This is the same handling `PlaybackController` has had all along
        /// for audio. Video simply never got it.
        private func watchForInterruption(player: AVPlayer) {
            let session = AVAudioSession.sharedInstance()

            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main,
            ) { [weak player] note in
                // Only these cross the hop. A `Notification` is not Sendable
                // and neither is the (non-isolated) coordinator, so sending
                // `self` here is a data race the compiler rightly rejects --
                // the two UInts and a weak player reference are enough.
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

                Task { @MainActor in
                    Coordinator.handleInterruption(
                        typeRaw: typeRaw,
                        optionsRaw: optionsRaw,
                        player: player,
                    )
                }
            }
        }

        @MainActor
        private static func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?, player: AVPlayer?) {
            guard let typeRaw,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
                  let player
            else { return }

            switch type {
            case .began:
                resumeFlag.wasPlaying = player.timeControlStatus == .playing

            case .ended:
                // Only resume what was actually playing, and only when the
                // system says we should -- somebody who switched away
                // deliberately does not want this starting up behind them.
                guard resumeFlag.wasPlaying else { return }

                resumeFlag.wasPlaying = false

                guard let optionsRaw,
                      AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
                else { return }

                // The session first: resuming the player without it gives a
                // moving picture and silence, which is the reported bug.
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()

            @unknown default:
                break
            }
        }

        /// Reports a playback that fails, instead of showing a black screen.
        ///
        /// Three things are watched, because they fail differently:
        ///
        ///  - **`currentItem.status`** goes `.failed` when the asset itself
        ///    cannot be loaded at all -- a 404, a container AVFoundation
        ///    refuses, a URL that is not what it claims.
        ///  - **`AVPlayerItemFailedToPlayToEndTime`** fires when playback
        ///    starts and then dies part-way, which a status check misses.
        ///  - **`errorLog()`** carries the HTTP detail for an HLS stream:
        ///    which segment failed and with what status. For the segment-auth
        ///    bug this is the line that would have said `302` instead of
        ///    leaving a silent black rectangle.
        ///
        /// Sent to the server as a diagnostic, because the phone that hit the
        /// failure is not the machine anybody is debugging on.
        private func watchForFailure(player: AVPlayer, item: MediaItem) {
            statusObserver = player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
                guard player.currentItem?.status == .failed else { return }

                self?.report(
                    failure: player.currentItem?.error,
                    item: item,
                    stage: "asset failed to load",
                    log: player.currentItem?.errorLog(),
                )
            }

            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: nil,
                queue: .main,
            ) { [weak self] note in
                let playerItem = note.object as? AVPlayerItem

                self?.report(
                    failure: note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error,
                    item: item,
                    stage: "stopped part-way",
                    log: playerItem?.errorLog(),
                )
            }
        }

        /// One failure, in a line somebody can act on.
        private func report(
            failure: Error?,
            item: MediaItem,
            stage: String,
            log: AVPlayerItemErrorLog?,
        ) {
            var parts = [
                "video \(stage)",
                "item \(item.id) \(item.title)",
            ]

            if let failure {
                parts.append("error: \(failure.localizedDescription)")
            }

            // The last few HLS errors, which is where an HTTP status appears.
            // Only the tail: a stream that has been failing for a while has
            // hundreds, and the recent ones are the ones that matter.
            if let events = log?.events.suffix(3) {
                for event in events {
                    var detail = "HLS"

                    if event.errorStatusCode != 0 {
                        detail += " HTTP \(event.errorStatusCode)"
                    }

                    if let comment = event.errorComment {
                        detail += ": \(comment)"
                    }

                    if let uri = event.uri {
                        detail += " [\(uri)]"
                    }

                    parts.append(detail)
                }
            }

            let reason = parts.joined(separator: " | ")

            // An explicit hop rather than `MainActor.assumeIsolated`: KVO and
            // notification callbacks do not promise which isolation domain
            // they arrive on, and assuming wrongly **traps**. The same hazard
            // is written down on the subtitle observer above, for the same
            // reason.
            Task { @MainActor in
                DeviceReporter.shared.sendDiagnostics(reason: reason)
            }
        }

        func stop() {
            if let timeObserver { player?.removeTimeObserver(timeObserver) }
            if let subtitleObserver { player?.removeTimeObserver(subtitleObserver) }
            timeObserver = nil
            subtitleObserver = nil

            // The failure watchers too, or each opened video leaves a live
            // KVO observation and a notification registration behind -- and a
            // stale one would report a later film's failure against this
            // item's id.
            statusObserver?.invalidate()
            statusObserver = nil

            if let failureObserver {
                NotificationCenter.default.removeObserver(failureObserver)
            }

            failureObserver = nil

            if let interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
            }

            interruptionObserver = nil
        }
    }
}
