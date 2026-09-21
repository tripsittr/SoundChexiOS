// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Owns playback for the whole app.
///
/// One AVPlayer, a queue, and the now-playing state the bar reads. Streaming
/// pulls from the token-authed `/api/v1/items/{id}/stream` route, which supports
/// Range requests so AVPlayer can seek without refetching. Position is reported
/// back to the server every few seconds so a track resumes where it stopped.
///
/// `@MainActor` because it drives the UI; the AVPlayer callbacks are hopped back
/// onto the main actor.
@MainActor
@Observable
final class PlaybackController {
    /// What is playing now, if anything.
    private(set) var current: MediaItem?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0

    /// Shuffle and repeat, surfaced for the now-playing controls.
    private(set) var isShuffled = false
    enum RepeatMode { case off, all, one }
    private(set) var repeatMode: RepeatMode = .off

    private var api: APIClient?
    private var queue: [MediaItem] = []
    private var index = 0
    /// The queue as it was handed in, so shuffle can be toggled off again.
    private var originalQueue: [MediaItem] = []

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var lastReportedSecond = -1

    /// The item whose cover is currently attached to the now-playing info, so a
    /// text-only refresh keeps the artwork and a track change reloads it. Not UI
    /// state — internal bookkeeping for the lock screen.
    @ObservationIgnored private var artworkItemID: Int?

    init() {
        configureSession()
        observeTime()
        configureRemoteCommands()
    }

    func attach(api: APIClient?) {
        self.api = api
    }

    // MARK: - Controls

    /// Plays a list from a starting index — a whole album, or one tapped song
    /// with the rest queued behind it.
    func play(_ items: [MediaItem], startAt start: Int = 0) {
        guard !items.isEmpty, let api else { return }

        originalQueue = items
        queue = items
        index = min(max(start, 0), items.count - 1)

        // A new context resets shuffle to whatever the toggle is now: if shuffle
        // is on, shuffle the rest behind the tapped track.
        if isShuffled { applyShuffle(keepingCurrent: true) }

        loadCurrent(api: api)
    }

    /// Toggles shuffle. Shuffling keeps the current track playing and reorders
    /// what's behind it; un-shuffling restores the original order from here on.
    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            applyShuffle(keepingCurrent: true)
        } else if let current, let restored = originalQueue.firstIndex(of: current) {
            queue = originalQueue
            index = restored
        }
    }

    /// Cycles repeat: off → all → one → off.
    func cycleRepeat() {
        repeatMode = switch repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    private func applyShuffle(keepingCurrent: Bool) {
        guard !queue.isEmpty else { return }
        let current = keepingCurrent ? queue[safe: index] : nil
        var rest = queue.enumerated().filter { $0.offset != index }.map(\.element)
        rest.shuffle()
        queue = (current.map { [$0] } ?? []) + rest
        index = 0
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    /// Inserts an item to play right after the current one.
    ///
    /// If nothing is playing, it just starts. Otherwise it slots in at the front
    /// of what remains, so "play next" jumps the rest of the queue.
    func playNext(_ item: MediaItem) {
        guard let api else { return }
        if current == nil {
            play([item])
        } else {
            queue.insert(item, at: index + 1)
            _ = api // keep the guard meaningful; loading happens on advance
        }
    }

    /// Appends an item to the end of the queue.
    func addToQueue(_ item: MediaItem) {
        if current == nil, let api {
            _ = api
            play([item])
        } else {
            queue.append(item)
        }
    }

    /// What is coming up after the current track, for the queue view.
    var upNext: [MediaItem] {
        guard index + 1 <= queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    func next() {
        guard let api else { return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            // Wrap to the top of the queue.
            index = 0
        } else {
            return
        }
        loadCurrent(api: api)
    }

    func previous() {
        // Restart the track first; only jump back if we're already near its start.
        if position > 3 {
            seek(to: 0)
            return
        }
        guard index > 0, let api else { return }
        index -= 1
        loadCurrent(api: api)
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    // MARK: - Loading

    private func loadCurrent(api: APIClient) {
        let item = queue[index]
        current = item

        let asset: AVURLAsset

        if let local = DownloadStore.shared.localURL(for: item.id) {
            // Downloaded: play from disk. Works with no network, and needs no
            // auth header since it is a local file.
            asset = AVURLAsset(url: local)
        } else {
            guard let url = api.streamURL(itemID: item.id) else { return }

            // The stream route authenticates with a Sanctum bearer *header* — a
            // query-param token is ignored, which is why playback started but no
            // audio ever arrived (the request 401'd). AVURLAsset lets us attach
            // the header to every request it makes for the media, including range
            // requests during a seek.
            var options: [String: Any] = [:]
            if let token = api.token {
                options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": "Bearer \(token)"]
            }
            asset = AVURLAsset(url: url, options: options)
        }

        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        // Activate the session now, right before audio starts — a failed
        // activation at launch would otherwise mute everything silently.
        activateSession()

        // Resume where this track was left off, then play.
        Task {
            let resume = (try? await api.progress(itemID: item.id))?.position ?? 0
            if resume > 3 { seek(to: Double(resume)) }
            player.play()
            isPlaying = true
            await readDuration(of: playerItem)
            updateNowPlayingInfo()
        }
    }

    private func readDuration(of item: AVPlayerItem) async {
        let seconds = (try? await item.asset.load(.duration).seconds) ?? 0
        if seconds.isFinite { duration = seconds }
    }

    // MARK: - Time / progress

    private func observeTime() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.position = time.seconds.isFinite ? time.seconds : 0
                self.reportProgressIfNeeded()
                self.advanceAtEnd()
            }
        }
    }

    private func reportProgressIfNeeded() {
        let second = Int(position)
        guard second != lastReportedSecond, second % 5 == 0, second > 0 else { return }
        lastReportedSecond = second

        guard let api, let item = current else { return }
        let pos = second
        let dur = Int(duration)
        Task { try? await api.saveProgress(itemID: item.id, position: pos, duration: dur) }
    }

    private func advanceAtEnd() {
        guard duration > 0, position >= duration - 0.5 else { return }

        // Repeat-one loops the same track; otherwise advance (which wraps when
        // repeat-all is on).
        if repeatMode == .one, let api {
            seek(to: 0)
            player.play()
            _ = api
        } else {
            next()
        }
    }

    // MARK: - System integration

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // `.longFormAudio` policy is what tells iOS this is music/podcast-style
        // playback that should keep going in the background and take over the
        // lock screen — the default policy does not, which is why audio stopped
        // when the screen locked.
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)

        // Re-activate on an interruption ending (a phone call, another app's
        // audio) so playback can resume rather than staying silent. The needed
        // values are pulled out here — a Notification cannot cross to the main
        // actor under Swift 6 strict concurrency, but the two UInts can.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main
        ) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw) }
        }
    }

    /// Makes sure the audio session is active. Called right before playback so a
    /// failed activation at launch does not permanently mute the app.
    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            isPlaying = false
            updateNowPlayingInfo()
        case .ended:
            // Resume only if the system says we should (the user did not switch
            // to something else deliberately).
            if let optionsRaw,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                activateSession()
                player.play()
                isPlaying = true
                updateNowPlayingInfo()
            }
        @unknown default:
            break
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
    }

    private func resume() { player.play(); isPlaying = true; updateNowPlayingInfo() }
    private func pause() { player.pause(); isPlaying = false; updateNowPlayingInfo() }

    private func updateNowPlayingInfo() {
        guard let item = current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyArtist] = item.subtitle ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyMediaType] = MPMediaType.music.rawValue

        // Carry the artwork already loaded for this item across a text-only
        // refresh (a play/pause, a position tick), so it does not blink out
        // between the sync update and the async reload below.
        if artworkItemID != item.id {
            info[MPMediaItemPropertyArtwork] = nil
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        loadNowPlayingArtwork(for: item)
    }

    /// Loads the current track's cover and attaches it to the now-playing info,
    /// so the lock screen and Control Center show artwork rather than a blank
    /// square (IOS bug: it was never set). Prefers the shared disk cache, so a
    /// cover already seen appears instantly and works offline.
    ///
    /// Guarded against a stale attach: if the track changes while the image is
    /// loading, the finished image is dropped rather than painted onto whatever
    /// is playing now.
    private func loadNowPlayingArtwork(for item: MediaItem) {
        guard let url = item.artwork else {
            artworkItemID = nil
            return
        }

        // Already showing this item's art — nothing to reload.
        if artworkItemID == item.id { return }

        Task { [weak self] in
            guard let image = await ImageCache.shared.image(for: url) else { return }
            guard let self, self.current?.id == item.id else { return }

            let artwork = Self.artwork(from: image)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            self.artworkItemID = item.id
        }
    }

    /// Wraps a cover image as `MPMediaItemArtwork`.
    ///
    /// `nonisolated` on purpose: MediaPlayer invokes the request-handler closure
    /// on its own background queue when it needs the bitmap. Built inside the
    /// `@MainActor` class, the closure inherits main-actor isolation and the
    /// concurrency runtime traps (EXC_BREAKPOINT) when it runs off-main — the
    /// crash after starting playback. A `nonisolated` factory whose `@Sendable`
    /// closure captures only the Sendable `UIImage` runs safely on any thread.
    private nonisolated static func artwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }
}

private extension Array {
    /// Bounds-checked subscript, nil when out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
