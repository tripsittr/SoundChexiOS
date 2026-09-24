// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation
import Observation

/// Owns downloaded media on disk.
///
/// Each track is downloaded from its token-authed stream URL to a file named by
/// its id, with a small JSON sidecar carrying the item's metadata so the
/// downloads list and offline browsing survive without the catalogue — the same
/// self-describing pattern the desktop store uses. A background URLSession keeps
/// a transfer going when the app is suspended and resumes a partial file.
///
/// State is kept in memory and mirrored to disk (the sidecars are the source of
/// truth on launch), and published so buttons and lists update as transfers
/// progress.
@MainActor
@Observable
final class DownloadStore: NSObject {
    static let shared = DownloadStore()

    /// Download state per item id, for the UI to observe.
    private(set) var states: [Int: DownloadState] = [:]

    enum DownloadState: Equatable {
        case idle
        /// Asked for, waiting for a slot in the concurrency window (S-341).
        case queued
        case downloading(progress: Double)
        case stored
        case failed
    }

    @ObservationIgnored private var api: APIClient?
    /// The metadata of everything stored, read from the sidecars — the offline
    /// library when there is no catalogue.
    private(set) var stored: [DownloadedItem] = []

    /// Maps an in-flight URLSession task to the item it is downloading.
    @ObservationIgnored private var tasks: [Int: Int] = [:] // taskIdentifier -> itemID

    /// Items waiting for a slot, in the order they were asked for (S-341).
    ///
    /// "Download all" on a large playlist used to hand every track to
    /// URLSession at once — hundreds of simultaneous requests against one
    /// server, most of which the server or the session refused, and each
    /// refusal marked its item failed immediately. A few at a time finishes
    /// the same work and actually completes.
    @ObservationIgnored private var waiting: [MediaItem] = []

    /// How many transfers may be in flight at once.
    private static let maxConcurrentDownloads = 3

    /// How many times a transfer is retried before it is called failed.
    private static let maxAttempts = 3

    @ObservationIgnored private var attempts: [Int: Int] = [:]

    /// The MediaItem behind each in-flight or queued transfer, so a retry can
    /// re-queue it directly.
    @ObservationIgnored private var inFlightItems: [Int: MediaItem] = [:]

    /// Items in flight right now.
    private var activeCount: Int { tasks.count }

    /// Cached bytes per stored item, so dashboard/storage summaries are O(1).
    @ObservationIgnored private var storedBytesByItemID: [Int: Int64] = [:]

    /// On-device download usage, in bytes.
    private(set) var storedBytesUsed: Int64 = 0

    /// Number of songs/files currently stored on this device.
    private(set) var storedItemCount = 0

    /// Current free bytes on the device volume used for downloads.
    private(set) var freeBytesAvailable: Int64 = .max

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.soundchex.ios.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        loadFromDisk()
        _ = session // wake the background session so it reattaches to running tasks
    }

    func attach(api: APIClient?) {
        self.api = api

        // With an API to build stream URLs from, pick up any transfer that was
        // interrupted before the app was last closed.
        if api != nil {
            resumeInterrupted()
        }
    }

    // MARK: - Queries

    func state(for itemID: Int) -> DownloadState {
        states[itemID] ?? .idle
    }

    func isStored(_ itemID: Int) -> Bool {
        state(for: itemID) == .stored
    }

    /// Stored entries currently usable on this device, newest first.
    var downloadedItems: [DownloadedItem] {
        stored.filter { isStored($0.id) }.reversed()
    }

    /// The on-disk media file for an item, when it is stored — for local playback.
    func localURL(for itemID: Int) -> URL? {
        let url = Self.mediaURL(for: itemID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The on-disk file only when it is worth handing to the player.
    ///
    /// A download that stored a refused request's error body is present but
    /// unplayable (S-327). Streaming instead turns a song that was silent into
    /// one that plays, and the bad file is cleared so it can be fetched again.
    func playableLocalURL(for itemID: Int) -> URL? {
        guard let url = localURL(for: itemID) else { return nil }

        guard !Self.isTooSmallToBeMedia(url) else {
            try? FileManager.default.removeItem(at: url)
            states[itemID] = .idle
            storedBytesByItemID[itemID] = nil
            refreshStorageSnapshot()
            AppLog.error("Stored file for #\(itemID) was not media; streaming instead", category: "downloads")
            DeviceReporter.shared.sendDiagnostics(
                reason: "stored file for item #\(itemID) was not media; removed local copy"
            )

            return nil
        }

        // Hand back a name AVFoundation will open. The stored file keeps its
        // format-agnostic `.media` name; this is a hard link beside it (S-360).
        return Self.playableURL(for: itemID) ?? url
    }

    // MARK: - Actions

    /// Starts (or resumes) a download for an item.
    ///
    /// If a partial transfer was interrupted earlier — the app was killed, the
    /// network dropped — its resume data is picked up so a large file continues
    /// from where it stopped rather than starting over. Otherwise it starts fresh.
    /// Queues one item. A single tap goes through the same window as a batch,
    /// so one download does not jump ahead of a running "download all".
    func download(_ item: MediaItem) {
        enqueue([item])
    }

    /// Actually starts a transfer. Only `pumpQueue()` calls this, so the
    /// concurrency window is respected.
    private func startTransfer(for item: MediaItem) {
        guard let api, let url = api.streamURL(itemID: item.id) else { return }
        guard state(for: item.id) != .stored else { return }

        let task: URLSessionDownloadTask

        if let resumeData = Self.resumeData(for: item.id) {
            // Continue the interrupted transfer. If the server no longer accepts
            // the resume (the file changed, or it doesn't support ranges), the
            // task fails and the next attempt starts fresh — see the delegate.
            task = session.downloadTask(withResumeData: resumeData)
            Self.clearResumeData(for: item.id)
        } else {
            var request = URLRequest(url: url)
            if let token = api.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            task = session.downloadTask(with: request)
        }

        tasks[task.taskIdentifier] = item.id
        states[item.id] = .downloading(progress: 0)

        // Write the sidecar up front so a download in progress is still listed
        // and can be resumed/identified after a relaunch.
        writeSidecar(for: item)

        task.resume()
    }

    /// Resumes every download that was interrupted and left resume data behind —
    /// called after a relaunch so a partial transfer picks up on its own.
    func resumeInterrupted() {
        for item in stored where state(for: item.id) != .stored && Self.hasResumeData(for: item.id) {
            download(item.asMediaItem)
        }
    }

    /// Downloads a batch — an album, or the whole library.
    ///
    /// Returns why it stopped so the caller can tell the user: `.started` with a
    /// count, or `.insufficientSpace`. Only items not already stored are queued.
    /// The per-file size is unknown until it downloads, so the gate is coarse: it
    /// refuses when free space is already below a floor, and warns the UI to keep
    /// an eye on it rather than promising the whole set will fit.
    func downloadAll(_ items: [MediaItem]) -> BatchResult {
        let pending = items.filter { $0.playable && state(for: $0.id) != .stored }
        guard !pending.isEmpty else { return .nothingToDo }

        // Refuse if the device is already nearly full — 1 GB floor. A real
        // per-file gate needs sizes the API does not send yet (server S-119).
        if freeBytes() < 1_000_000_000 {
            return .insufficientSpace
        }

        enqueue(pending)

        return .started(count: pending.count)
    }

    /// Adds items to the queue and starts as many as the concurrency window
    /// allows. Anything already stored, downloading or queued is skipped.
    private func enqueue(_ items: [MediaItem]) {
        for item in items where !waiting.contains(where: { $0.id == item.id }) {
            guard state(for: item.id) != .stored else { continue }
            guard !tasks.values.contains(item.id) else { continue }

            waiting.append(item)
            inFlightItems[item.id] = item
            states[item.id] = .queued
        }

        pumpQueue()
    }

    /// Starts queued transfers until the concurrency window is full.
    private func pumpQueue() {
        while activeCount < Self.maxConcurrentDownloads, !waiting.isEmpty {
            let next = waiting.removeFirst()

            guard state(for: next.id) != .stored else { continue }

            startTransfer(for: next)
        }
    }

    /// Called whenever a transfer leaves the window, so the next one starts.
    private func transferFinished(itemID: Int) {
        attempts[itemID] = nil
        inFlightItems[itemID] = nil
        pumpQueue()
    }

    /// Retries a transfer that failed for a reason worth retrying, or gives up
    /// and marks it failed.
    private func retryOrFail(_ itemID: Int) {
        let used = (attempts[itemID] ?? 0) + 1
        attempts[itemID] = used

        guard used < Self.maxAttempts, let item = startedItem(itemID) else {
            states[itemID] = .failed
            attempts[itemID] = nil
            pumpQueue()
            return
        }

        states[itemID] = .queued

        // Back off a little so a server that is refusing under load is not hit
        // again immediately.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(used) * 2))
            waiting.append(item)
            pumpQueue()
        }
    }

    /// The item a transfer was started for, kept so a retry can re-queue it
    /// without needing the catalogue.
    private func startedItem(_ itemID: Int) -> MediaItem? {
        inFlightItems[itemID]
    }

    enum BatchResult: Equatable {
        case started(count: Int)
        case insufficientSpace
        case nothingToDo
    }

    /// Free space on the store's volume, in bytes.
    private func freeBytes() -> Int64 {
        let values = try? Self.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }

    /// Refreshes cached on-device storage counters for dashboard/diagnostics.
    func refreshStorageSnapshot() {
        storedItemCount = storedBytesByItemID.count
        storedBytesUsed = storedBytesByItemID.values.reduce(0, +)
        freeBytesAvailable = freeBytes()
    }

    /// Removes a downloaded item from disk.
    func remove(_ itemID: Int) {
        try? FileManager.default.removeItem(at: Self.mediaURL(for: itemID))
        try? FileManager.default.removeItem(at: Self.sidecarURL(for: itemID))
        Self.clearResumeData(for: itemID)
        states[itemID] = .idle
        stored.removeAll { $0.id == itemID }
        storedBytesByItemID[itemID] = nil
        refreshStorageSnapshot()
    }

    // MARK: - Disk layout

    /// ~/Library/Application Support/downloads — excluded from iCloud backup
    /// because it is a redownloadable cache of the user's own library.
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return base
    }()

    static func mediaURL(for itemID: Int) -> URL {
        directory.appendingPathComponent("\(itemID).media")
    }

    /// A name AVFoundation will actually open the stored file under (S-360).
    ///
    /// Downloads are saved as `<id>.media`, a deliberately format-agnostic
    /// name. AVFoundation will not open it: with no extension it recognises
    /// and no type hint, `AVURLAsset` answers "Cannot Open" for a file that is
    /// a perfectly valid MP3 — verified byte-for-byte against the same data
    /// renamed `.mp3`, which loads and reports its duration.
    ///
    /// That is why downloaded music never played offline. Online it looked
    /// like it worked: local playback failed, and the recovery path quietly
    /// fell back to streaming, so the only symptom was that downloads were
    /// pointless. In airplane mode there is nothing to fall back to.
    ///
    /// Rather than rename 603 existing files, a hard link with a real
    /// extension is placed beside the download and handed to the player. Same
    /// bytes, no copy, and the `.media` file stays the one the rest of the
    /// store reasons about.
    static func playableURL(for itemID: Int) -> URL? {
        let source = mediaURL(for: itemID)

        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let linked = directory.appendingPathComponent("\(itemID).\(Self.fileExtension(for: source))")

        if FileManager.default.fileExists(atPath: linked.path) {
            return linked
        }

        do {
            try FileManager.default.linkItem(at: source, to: linked)

            return linked
        } catch {
            // A filesystem that refuses hard links, or a name already taken by
            // something else. Copying a whole track to play it is worse than
            // trying the original and letting the stream fallback handle it.
            AppLog.warning(
                "Could not link a playable name for #\(itemID): \(error.localizedDescription)",
                category: "downloads"
            )

            return source
        }
    }

    /// The extension to present a download under, read from the file itself.
    ///
    /// Sniffed rather than guessed from the item's type: the catalogue records
    /// what a thing *is*, not what container it arrived in, and naming an M4A
    /// `.mp3` puts us back where we started. Four magic numbers cover
    /// everything this server transcodes to or stores.
    private static func fileExtension(for url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "mp3" }

        defer { try? handle.close() }

        guard let head = try? handle.read(upToCount: 12), head.count >= 12 else { return "mp3" }

        let bytes = [UInt8](head)

        // ISO base media (M4A/M4B/MP4): "ftyp" at offset 4.
        if bytes[4...7] == [0x66, 0x74, 0x79, 0x70] {
            return "m4a"
        }

        // "OggS" — Vorbis or Opus.
        if bytes[0...3] == [0x4F, 0x67, 0x67, 0x53] {
            return "ogg"
        }

        // "fLaC".
        if bytes[0...3] == [0x66, 0x4C, 0x61, 0x43] {
            return "flac"
        }

        // "RIFF" … "WAVE".
        if bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x41, 0x56, 0x45] {
            return "wav"
        }

        // An ID3 tag ("ID3") or a bare MPEG frame sync — both are MP3, and it
        // is the overwhelmingly common case here.
        return "mp3"
    }

    static func sidecarURL(for itemID: Int) -> URL {
        directory.appendingPathComponent("\(itemID).json")
    }

    /// Where a partial transfer's resume data is parked between attempts.
    private static func resumeURL(for itemID: Int) -> URL {
        directory.appendingPathComponent("\(itemID).resume")
    }

    private static func saveResumeData(_ data: Data, for itemID: Int) {
        try? data.write(to: resumeURL(for: itemID))
    }

    private static func resumeData(for itemID: Int) -> Data? {
        try? Data(contentsOf: resumeURL(for: itemID))
    }

    private static func hasResumeData(for itemID: Int) -> Bool {
        FileManager.default.fileExists(atPath: resumeURL(for: itemID).path)
    }

    private static func clearResumeData(for itemID: Int) {
        try? FileManager.default.removeItem(at: resumeURL(for: itemID))
    }

    private func writeSidecar(for item: MediaItem) {
        let downloaded = DownloadedItem(
            id: item.id, type: item.type, title: item.title,
            subtitle: item.subtitle, artwork: item.artwork,
            durationMs: item.meta?.durationMs
        )
        if let data = try? JSONEncoder().encode(downloaded) {
            try? data.write(to: Self.sidecarURL(for: item.id))
        }
        if !stored.contains(where: { $0.id == item.id }) {
            stored.append(downloaded)
        }
    }

    /// Rebuilds the in-memory state from the sidecars and media files on launch.
    private func loadFromDisk() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.directory,
                                                        includingPropertiesForKeys: nil) else { return }

        storedBytesByItemID = [:]

        for sidecar in entries where sidecar.pathExtension == "json" {
            guard let data = try? Data(contentsOf: sidecar),
                  let item = try? JSONDecoder().decode(DownloadedItem.self, from: data) else { continue }
            stored.append(item)

            // Stored only if the media file actually landed; a lone sidecar means
            // an interrupted download.
            let media = Self.mediaURL(for: item.id)

            guard fm.fileExists(atPath: media.path) else {
                states[item.id] = .idle
                continue
            }

            // Builds before S-327 stored a refused request's error body as the
            // song — a few dozen bytes of JSON that played as silence. Clear
            // those out rather than leaving the library full of tracks that
            // cannot play; they can simply be downloaded again.
            if Self.isTooSmallToBeMedia(media) {
                try? fm.removeItem(at: media)
                states[item.id] = .idle
                AppLog.info("Discarded a failed download for #\(item.id)", category: "downloads")
                continue
            }

            states[item.id] = .stored
            if let size = (try? media.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                storedBytesByItemID[item.id] = Int64(size)
            }
        }

        refreshStorageSnapshot()
    }

    /// Whether a stored file is too small to be real media.
    ///
    /// An error body is tens of bytes; the shortest plausible encoded track is
    /// still tens of kilobytes, so this separates the two without having to
    /// decode anything.
    private static func isTooSmallToBeMedia(_ url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return size < 16_384
    }
}

/// The metadata stored beside a downloaded file — the offline library entry.
struct DownloadedItem: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let type: MediaType
    let title: String
    let subtitle: String?
    let artwork: URL?
    let durationMs: Int?
}

// MARK: - Background download delegate

extension DownloadStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // Move the file synchronously here — `location` is deleted when this
        // returns — then update state on the main actor.
        let identifier = downloadTask.taskIdentifier
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: temp)

        // URLSession reports a 404 as a *successful* download whose body is the
        // error page. Without this check that body was stored as the song: the
        // app believed the track was downloaded and played a 21-byte JSON error
        // as audio, which is silence, a motionless timeline, and a UI insisting
        // it is playing (S-327).
        let response = downloadTask.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        let mime = response?.mimeType ?? ""
        let isAudio = mime.hasPrefix("audio/") || mime.hasPrefix("video/")
            || mime == "application/octet-stream"

        Task { @MainActor in
            guard let itemID = tasks[identifier] else { try? FileManager.default.removeItem(at: temp); return }
            tasks[identifier] = nil

            guard (200...299).contains(status), isAudio else {
                try? FileManager.default.removeItem(at: temp)

                // A 5xx or a throttle is worth another go; a 404 (the file is
                // missing on the server) or a 401 is not.
                let worthRetrying = status >= 500 || status == 429 || status == 0

                if worthRetrying {
                    AppLog.error(
                        "Download of #\(itemID) failed with HTTP \(status); will retry",
                        category: "downloads"
                    )
                    retryOrFail(itemID)

                    return
                }

                states[itemID] = .failed
                transferFinished(itemID: itemID)
                AppLog.error(
                    "Download of #\(itemID) refused: HTTP \(status), \(mime.isEmpty ? "no content type" : mime)",
                    category: "downloads"
                )
                DeviceReporter.shared.sendDiagnostics(
                    reason: "download refused for item #\(itemID): HTTP \(status), \(mime.isEmpty ? "no content type" : mime)"
                )
                return
            }

            let dest = Self.mediaURL(for: itemID)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: temp, to: dest)
                states[itemID] = .stored
                if let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                    storedBytesByItemID[itemID] = Int64(size)
                } else {
                    storedBytesByItemID[itemID] = nil
                }
                refreshStorageSnapshot()
            } catch {
                states[itemID] = .failed
            }

            transferFinished(itemID: itemID)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            if let itemID = tasks[identifier] {
                states[itemID] = .downloading(progress: progress)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        guard let error else { return }
        let identifier = task.taskIdentifier

        // If the interruption produced resume data, the transfer can pick up
        // where it stopped rather than restarting — capture it before clearing
        // the task. A cancel-without-resume (the user removed the download) has
        // none, and simply fails.
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data

        Task { @MainActor in
            guard let itemID = tasks[identifier] else { return }

            tasks[identifier] = nil

            if let resumeData {
                Self.saveResumeData(resumeData, for: itemID)
            }

            // A transport error (a dropped connection, a timeout under load) is
            // worth another attempt; the queue only gives up after a few.
            retryOrFail(itemID)
        }
    }
}
