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

    private var api: APIClient?
    private var queue: [MediaItem] = []
    private var index = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var lastReportedSecond = -1

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

        queue = items
        index = min(max(start, 0), items.count - 1)
        loadCurrent(api: api)
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func next() {
        guard index + 1 < queue.count, let api else { return }
        index += 1
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

        guard let url = api.streamURL(itemID: item.id) else { return }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

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
        next()
    }

    // MARK: - System integration

    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
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
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.subtitle ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info[MPMediaItemPropertyMediaType] = MPMediaType.music.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
