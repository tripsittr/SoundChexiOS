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
    /// Off, ordinary shuffle, or shuffle weighted by what this profile plays.
    ///
    /// Three states on one button, cycled by pressing it, the way repeat
    /// already works — so the third mode lives where one already did rather
    /// than needing a new control on a crowded transport (S-289).
    enum ShuffleMode { case off, on, smart }

    private(set) var shuffleMode: ShuffleMode = .off

    /// Whether shuffle is on at all, in either form.
    var isShuffled: Bool { shuffleMode != .off }
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

    /// Bumped on every load, so work started for an earlier track can tell that
    /// it has been superseded and stop.
    ///
    /// Loading is asynchronous — the saved position is fetched over the network
    /// before playback starts — and a listener skipping twice quickly starts a
    /// second load while the first is still awaiting. Without this the older
    /// task would come back and seek or play against the newer track, which
    /// showed up as a skip that left the UI playing with no audio.
    @ObservationIgnored private var loadGeneration = 0

    /// The item the current load produced, so the end-of-track check can tell a
    /// real ending from the moment between tracks.
    @ObservationIgnored private var currentPlayerItem: AVPlayerItem?

    /// Whether audio was actually playing when an interruption began, so a
    /// paused track is not started by the interruption ending (S-345).
    @ObservationIgnored private var wasPlayingBeforeInterruption = false

    /// Watches the player item for failure and for a stall that never clears.
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    /// Tracks the real AVPlayer state so the UI only says "playing" when the
    /// system has actually moved from waiting into the playing state.
    @ObservationIgnored private var playbackStateObservation: NSKeyValueObservation?

    /// Fires if a newly requested track never reaches audible playback.
    @ObservationIgnored private var startupDiagnosticTask: Task<Void, Never>?

    /// Human-readable source currently handed to AVPlayer (local file or stream URL).
    @ObservationIgnored private var currentPlaybackTarget = "unknown"

    /// Prevents an infinite retry loop when a broken local file cannot open.
    @ObservationIgnored private var recoveringFromLocalFailureItemID: Int?

    /// Forces one stream attempt even when a local download exists.
    @ObservationIgnored private var forceStreamForItemID: Int?

    /// The item whose cover is currently attached to the now-playing info, so a
    /// text-only refresh keeps the artwork and a track change reloads it. Not UI
    /// state — internal bookkeeping for the lock screen.
    @ObservationIgnored private var artworkItemID: Int?

    init() {
        configureSession()
        observeTime()
        observePlaybackState()
        configureRemoteCommands()
    }

    private func observePlaybackState() {
        playbackStateObservation?.invalidate()
        playbackStateObservation = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncPlaybackState()
            }
        }
    }

    private func syncPlaybackState() {
        let shouldBePlaying = player.timeControlStatus == .playing
        if shouldBePlaying != isPlaying {
            isPlaying = shouldBePlaying
            updateNowPlayingInfo()
        }
    }

    func attach(api: APIClient?) {
        self.api = api
    }

    // MARK: - Controls

    /// Plays a list from a starting index — a whole album, or one tapped song
    /// with the rest queued behind it.
    func play(_ items: [MediaItem], startAt start: Int = 0) {
        guard !items.isEmpty else { return }
        guard let api else {
            AppLog.error("Playback ignored because API client is unavailable", category: "playback")
            DeviceReporter.shared.sendDiagnostics(reason: "playback request ignored: api client unavailable")
            return
        }

        originalQueue = items
        queue = items
        index = min(max(start, 0), items.count - 1)

        // A new context resets shuffle to whatever the toggle is now: if shuffle
        // is on, shuffle the rest behind the tapped track.
        if isShuffled { applyShuffle(keepingCurrent: true) }

        loadCurrent(api: api)
    }

    /// Cycles shuffle: off → on → smart → off.
    ///
    /// Shuffling keeps the current track playing and reorders what is behind
    /// it; turning it off restores the original order from here on. Smart asks
    /// the server for a queue weighted by this profile's play history —
    /// weighting it here would mean the phone holding the whole library and
    /// every play (S-289).
    func toggleShuffle() {
        shuffleMode = switch shuffleMode {
        case .off: .on
        case .on: .smart
        case .smart: .off
        }

        switch shuffleMode {
        case .on:
            applyShuffle(keepingCurrent: true)
        case .smart:
            // The queue is left as it is until the weighted one arrives: a
            // button that empties the player mid-request is worse than one
            // that takes a moment.
            Task { await loadSmartQueue() }
        case .off:
            if let current, let restored = originalQueue.firstIndex(of: current) {
                queue = originalQueue
                index = restored
            }
        }
    }

    /// Replaces what is behind the current track with a server-weighted queue.
    ///
    /// A failure falls back to ordinary shuffle rather than staying in "smart"
    /// while behaving uniformly — the listener pressed a button and something
    /// should happen, and a mode that quietly means nothing is worse than an
    /// honest one.
    private func loadSmartQueue() async {
        guard let api else { return }

        do {
            let items = try await api.shuffleLibrary(smart: true)

            guard !items.isEmpty else { throw APIClient.APIError.http(status: 204) }

            let playing = current
            let rest = items.filter { $0.id != playing?.id }

            queue = playing.map { [$0] + rest } ?? rest
            originalQueue = queue
            index = 0
        } catch {
            AppLog.warning("Smart shuffle failed, falling back: \(error.localizedDescription)", category: "playback")

            shuffleMode = .on
            applyShuffle(keepingCurrent: true)
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
        // Read the player rather than the flag. If playback stalled, the flag
        // can say "playing" while nothing is — toggling from the flag then just
        // relabels the button, and the listener has to press twice to recover.
        if player.timeControlStatus == .playing {
            pause()
        } else {
            // A track that ran to its end needs rewinding, or play() resumes at
            // the end and stops again immediately.
            if duration > 0, position >= duration - 0.5 { seek(to: 0) }
            resume()
        }
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

    /// Queues several tracks to play next, keeping their order (S-385).
    ///
    /// Inserted as a block rather than one at a time: calling `playNext` in a
    /// loop puts each new track ahead of the last, so an album would queue
    /// backwards.
    func playNext(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        if current == nil {
            play(items)

            return
        }

        queue.insert(contentsOf: items, at: min(index + 1, queue.count))
    }

    /// Appends several tracks to the end of the queue, keeping their order.
    func addToQueue(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        if current == nil {
            play(items)

            return
        }

        queue.append(contentsOf: items)
    }

    /// What is coming up after the current track, for the queue view.
    var upNext: [MediaItem] {
        guard index + 1 <= queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    /// Jumps to a queued item and starts playing it immediately.
    func playFromQueue(itemID: Int) {
        guard let api, let target = queue.firstIndex(where: { $0.id == itemID }) else { return }
        guard target != index else { return }
        index = target
        loadCurrent(api: api)
    }

    /// Reorders the upcoming queue (everything after the current track).
    func moveUpNext(from source: IndexSet, to destination: Int) {
        let start = index + 1
        guard start < queue.count else { return }

        var upcoming = Array(queue[start...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(start..<queue.count, with: upcoming)
        if !isShuffled { originalQueue = queue }
    }

    /// Removes an item from the queue.
    func removeFromQueue(itemID: Int) {
        guard let target = queue.firstIndex(where: { $0.id == itemID }) else { return }

        if target < index {
            queue.remove(at: target)
            index -= 1
        } else if target == index {
            queue.remove(at: target)
            if queue.isEmpty {
                startupDiagnosticTask?.cancel()
                statusObservation?.invalidate()
                player.replaceCurrentItem(with: nil)
                current = nil
                duration = 0
                position = 0
                isPlaying = false
                updateNowPlayingInfo()
            } else if let api {
                index = min(index, queue.count - 1)
                loadCurrent(api: api)
            }
        } else {
            queue.remove(at: target)
        }

        if !isShuffled { originalQueue = queue }
    }

    /// Moves an upcoming item to the first "up next" position.
    func moveToPlayNext(itemID: Int) {
        guard let target = queue.firstIndex(where: { $0.id == itemID }) else { return }
        let nextSlot = index + 1
        guard target > nextSlot, nextSlot < queue.count else { return }

        let item = queue.remove(at: target)
        queue.insert(item, at: nextSlot)
        if !isShuffled { originalQueue = queue }
    }

    func next() {
        guard let api else { return }
        if index + 1 < queue.count {
            index += 1
        } else if repeatMode == .all {
            // Wrap to the top of the queue.
            index = 0
        } else {
            // The end of the queue with repeat off. Stop rather than returning
            // silently, which left the bar claiming to play a finished track.
            pause()
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
        // Move the published position with the request, not only when the next
        // tick lands. Releasing the scrubber otherwise let the thumb snap back
        // to where the song was for a frame before the seek reported in.
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            // Tell the lock screen where we actually landed, once the player
            // has landed there. Without this the lock screen and Control
            // Centre kept the elapsed time from before the scrub and only
            // caught up when pausing and playing forced a refresh — the
            // system extrapolates from the last elapsed time it was given, so
            // a stale one drifts on happily (S-363).
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
        }

        // …and immediately, so the lock screen does not show the old time for
        // the length of the seek.
        updateNowPlayingInfo()
    }

    // MARK: - Loading

    /// Loads the current queue entry.
    ///
    /// `startingAt` exists only for restoring a track that was interrupted
    /// mid-play (S-342); every ordinary load starts at zero, because moving
    /// between songs always restarts them.
    private func loadCurrent(api: APIClient, startingAt startPosition: Double = 0, autoplay: Bool = true) {
        guard queue.indices.contains(index) else { return }

        let item = queue[index]
        current = item
        startupDiagnosticTask?.cancel()
        if recoveringFromLocalFailureItemID != item.id {
            recoveringFromLocalFailureItemID = nil
        }

        // A new track starts from nothing known. Without this the previous
        // track's values survived the change: going back a song showed the
        // position it was skipped at, or showed as already finished, and the
        // stale duration could fire the end-of-track check immediately and skip
        // the song that had just started.
        position = 0
        duration = 0
        lastReportedSecond = -1

        // Anything still in flight for the previous track is now stale.
        loadGeneration &+= 1
        let generation = loadGeneration

        AppLog.info("Play #\(item.id) “\(item.title)” (\(index + 1)/\(queue.count))", category: "playback")

        let asset: AVURLAsset
        let sourceDescription: String

          if forceStreamForItemID != item.id,
              let local = DownloadStore.shared.playableLocalURL(for: item.id) {
            // Downloaded: play from disk. Works with no network, and needs no
            // auth header since it is a local file.
            asset = AVURLAsset(url: local)
            sourceDescription = "local"
            currentPlaybackTarget = "local:\(local.lastPathComponent)"
        } else {
            guard let url = api.streamURL(itemID: item.id) else {
                AppLog.error("Playback failed: stream URL missing for #\(item.id)", category: "playback")
                DeviceReporter.shared.sendDiagnostics(reason: "playback failed for item #\(item.id): stream URL missing")
                isPlaying = false
                updateNowPlayingInfo()
                return
            }

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
            sourceDescription = "stream"
            currentPlaybackTarget = "stream:\(url.absoluteString)"
            if forceStreamForItemID == item.id {
                forceStreamForItemID = nil
            }
        }

        let playerItem = AVPlayerItem(asset: asset)
        currentPlayerItem = playerItem
        observeStatus(of: playerItem, generation: generation)
        player.replaceCurrentItem(with: playerItem)

        // Activate the session now, right before audio starts — a failed
        // activation at launch would otherwise mute everything silently.
        activateSession()

        // Resume where this track was left off, then play.
        Task {
            // Only long-form media resumes. A song is meant to start at the
            // start: skipping past one records the position it was abandoned
            // at, so resuming would drop the listener back mid-song — or, for a
            // track that had played out, at its very end, which looked like the
            // song was already over the moment it was selected.
            // A restored track carries its own position; otherwise only
            // long-form media resumes. A song is meant to start at the start —
            // skipping past one records the position it was abandoned at, so
            // resuming would drop the listener back mid-song.
            let resume: Double = startPosition > 0
                ? startPosition
                : (item.type == .book
                    ? Double((try? await api.progress(itemID: item.id))?.position ?? 0)
                    : 0)

            // The await above gives another skip time to start its own load. If
            // one did, this task belongs to a track the listener has already
            // left — seeking or playing here would fight the new one.
            guard generation == self.loadGeneration else { return }

            if resume > 3 {
                seek(to: resume)
                position = resume
            }

            guard autoplay else {
                // Restored from a previous run: the track is ready where it
                // stopped, but nothing plays until the listener says so.
                await readDuration(of: playerItem)
                syncPlaybackState()
                updateNowPlayingInfo()
                return
            }

            player.play()
            syncPlaybackState()
            scheduleStartupDiagnostic(generation: generation, itemID: item.id, source: sourceDescription)
            await readDuration(of: playerItem)

            guard generation == self.loadGeneration else { return }
            updateNowPlayingInfo()
        }
    }

    /// Reports a track that cannot play instead of leaving the UI insisting it
    /// is playing.
    ///
    /// A failed item (an expired token, a file that has gone, a stream that
    ///404s) leaves AVPlayer with nothing to do: no audio, no time observer
    /// ticks, and — before this — `isPlaying` still true and a frozen timeline.
    private func observeStatus(of item: AVPlayerItem, generation: Int) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }

            Task { @MainActor [weak self] in
                guard let self, generation == self.loadGeneration else { return }

                AppLog.error(
                    "Playback failed: \(observed.error?.localizedDescription ?? "unknown error")",
                    category: "playback"
                )

                if self.currentPlaybackTarget.hasPrefix("local:"),
                   let itemID = self.current?.id,
                   self.recoveringFromLocalFailureItemID != itemID,
                   let api = self.api {
                    self.recoveringFromLocalFailureItemID = itemID
                    AppLog.error(
                        "Local playback failed for #\(itemID); retrying stream without deleting local copy",
                        category: "playback"
                    )
                    DeviceReporter.shared.sendDiagnostics(
                        reason: "local playback failed for item #\(itemID); retrying stream without deleting local copy"
                    )

                    self.forceStreamForItemID = itemID
                    self.loadCurrent(api: api)
                    return
                }

                DeviceReporter.shared.sendDiagnostics(
                    reason: "playback failed for item #\(self.current?.id ?? -1): \(observed.error?.localizedDescription ?? "unknown error") target=\(self.currentPlaybackTarget)"
                )

                self.startupDiagnosticTask?.cancel()

                self.isPlaying = false
                self.updateNowPlayingInfo()
            }
        }
    }

    /// Captures silent-start failures where `AVPlayerItem.status` never flips to
    /// `.failed` but playback still does not begin.
    private func scheduleStartupDiagnostic(generation: Int, itemID: Int, source: String) {
        startupDiagnosticTask?.cancel()
        startupDiagnosticTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, generation == self.loadGeneration, self.current?.id == itemID else { return }

            let neverAdvanced = self.position < 0.25
            let notPlaying = self.player.timeControlStatus != .playing
            guard neverAdvanced || notPlaying else { return }

            let waiting = self.player.reasonForWaitingToPlay?.rawValue ?? "none"
            let itemStatus = self.player.currentItem?.status.rawValue ?? -1
            let error = self.player.currentItem?.error?.localizedDescription ?? "none"

            self.isPlaying = false
            self.updateNowPlayingInfo()

            AppLog.error(
                "Playback stalled at start for #\(itemID) (source=\(source), waiting=\(waiting), status=\(itemStatus), error=\(error))",
                category: "playback"
            )
            DeviceReporter.shared.sendDiagnostics(
                reason: "playback stalled for item #\(itemID): source=\(source), waiting=\(waiting), status=\(itemStatus), error=\(error), target=\(self.currentPlaybackTarget)"
            )
        }
    }

    private func readDuration(of item: AVPlayerItem) async {
        let seconds = (try? await item.asset.load(.duration).seconds) ?? 0
        if seconds.isFinite { duration = seconds }
    }

    // MARK: - Time / progress

    private func observeTime() {
        // A quarter-second tick keeps synced lyrics landing on the right line
        // without noticeable lag. Progress reporting is still gated to whole
        // seconds below, so the finer tick costs nothing there.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            MainActor.assumeIsolated {
                // The scrubber belongs to the track on screen, and to no other.
                // A tick can arrive for the item being replaced — during a skip,
                // or from the old item just before `replaceCurrentItem` takes
                // effect — and writing that into `position` made the next song
                // start partway along, wherever the last one was abandoned.
                guard let item = self.currentPlayerItem,
                      self.player.currentItem === item else { return }

                self.position = time.seconds.isFinite ? time.seconds : 0
                self.reportProgressIfNeeded()
                self.advanceAtEnd()
                self.rememberPlaybackState()
            }
        }
    }

    // MARK: - Remembering where playback was (S-342)

    /// What was playing, and where, so closing or crashing the app does not
    /// lose the listener's place.
    ///
    /// Deliberately *not* a resume position for the track itself: between songs
    /// playback always restarts, and skipping a song restarts it. This is only
    /// the one track that was interrupted mid-play, restored exactly where it
    /// stopped and left paused so nothing starts playing on its own.
    private struct RememberedPlayback: Codable {
        let itemID: Int
        let position: Double
        let queue: [Int]
        let index: Int
    }

    private static let rememberedKey = "playback.remembered"

    /// Throttles the write — the time observer ticks four times a second and
    /// UserDefaults does not need that.
    @ObservationIgnored private var lastRememberedSecond = -1

    private func rememberPlaybackState() {
        guard let item = current else { return }

        let second = Int(position)
        guard second != lastRememberedSecond else { return }
        lastRememberedSecond = second

        writeRememberedState(itemID: item.id, position: position)
    }

    /// Writes the remembered position now, whatever the throttle says — for
    /// pausing and for the app leaving the foreground, where the next tick may
    /// never come.
    func rememberPlaybackStateNow() {
        guard let item = current else { return }

        writeRememberedState(itemID: item.id, position: position)
    }

    private func writeRememberedState(itemID: Int, position: Double) {
        // A track sitting at its end has nothing worth restoring — it would
        // reopen finished. Between songs means starting over.
        guard position > 3, duration == 0 || position < duration - 1 else {
            UserDefaults.standard.removeObject(forKey: Self.rememberedKey)
            return
        }

        let state = RememberedPlayback(
            itemID: itemID,
            position: position,
            queue: queue.map(\.id),
            index: index
        )

        guard let data = try? JSONEncoder().encode(state) else { return }

        UserDefaults.standard.set(data, forKey: Self.rememberedKey)
    }

    /// Restores the interrupted track, paused, at the position it stopped.
    ///
    /// Called once the library is loaded, since the queue is rebuilt from ids.
    /// Nothing starts playing — the listener presses play.
    func restoreRememberedState(from library: [MediaItem]) {
        guard current == nil,
              let data = UserDefaults.standard.data(forKey: Self.rememberedKey),
              let state = try? JSONDecoder().decode(RememberedPlayback.self, from: data),
              let api else { return }

        let byID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        let restoredQueue = state.queue.compactMap { byID[$0] }

        guard let position = restoredQueue.firstIndex(where: { $0.id == state.itemID })
            ?? (byID[state.itemID].map { _ in 0 }) else { return }

        queue = restoredQueue.isEmpty ? [byID[state.itemID]].compactMap { $0 } : restoredQueue
        originalQueue = queue
        index = restoredQueue.isEmpty ? 0 : position

        guard queue.indices.contains(index) else { return }

        loadCurrent(api: api, startingAt: state.position, autoplay: false)
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
        // Only the item this tick actually belongs to may end the track. A tick
        // can arrive while the player is between items, when `duration` still
        // describes the track just left — which read as "finished" and skipped
        // straight past the song that had only just started.
        guard let item = currentPlayerItem, player.currentItem === item else { return }

        guard duration > 0, position >= duration - 0.5 else { return }

        // Repeat-one loops the same track; otherwise advance (which wraps when
        // repeat-all is on).
        if repeatMode == .one {
            seek(to: 0)
            player.play()
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
            // Remember whether this interrupted actual playback. A paused track
            // that is interrupted must stay paused when the interruption ends.
            wasPlayingBeforeInterruption = player.timeControlStatus == .playing
            isPlaying = false
            updateNowPlayingInfo()
        case .ended:
            // Resume only if the system says we should (the user did not switch
            // to something else deliberately) *and* something was actually
            // playing when it began. Without the second test, a paused track
            // could start on its own when the app came back — which is how
            // reopening the app sometimes began playing the last song (S-345).
            guard wasPlayingBeforeInterruption else {
                wasPlayingBeforeInterruption = false
                return
            }

            wasPlayingBeforeInterruption = false

            if let optionsRaw,
               AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                activateSession()
                player.play()
                syncPlaybackState()
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

        // Scrubbing *from* the lock screen. Without a handler the system draws
        // the scrubber but drags do nothing, which reads as a broken control
        // rather than an absent feature (S-363).
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }

            self.seek(to: event.positionTime)

            return .success
        }
    }

    private func resume() {
        player.play()
        syncPlaybackState()
        if let id = current?.id {
            scheduleStartupDiagnostic(generation: loadGeneration, itemID: id, source: "resume")
        }
        updateNowPlayingInfo()
    }
    private func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
        // Pausing is exactly the state worth surviving a relaunch (S-342).
        rememberPlaybackStateNow()
    }

    private func updateNowPlayingInfo() {
        guard let item = current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyArtist] = item.subtitle ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyMediaType] = MPMediaType.music.rawValue

        // The album, and the two keys that travel with it (S-413).
        //
        // Car head units read `albumTitle` specifically. It was never set, so
        // a car over Bluetooth showed a blank album — which reads as missing
        // metadata rather than as an app that did not send it. Album artist
        // and track number are read by some units too, and the app already
        // has both.
        //
        // Set to nil rather than "" when absent: an empty string is a value,
        // and a head unit will faithfully display an empty album line where
        // nil lets it collapse the row.
        info[MPMediaItemPropertyAlbumTitle] = item.meta?.album
        info[MPMediaItemPropertyAlbumArtist] = item.meta?.groupingArtist
        info[MPMediaItemPropertyAlbumTrackNumber] = item.meta?.trackNumber

        if let year = item.meta?.releaseYear {
            info[MPMediaItemPropertyReleaseDate] = DateComponents(
                calendar: .current, year: year,
            ).date
        }

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
