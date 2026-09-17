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
    }

    // MARK: - Queries

    func state(for itemID: Int) -> DownloadState {
        states[itemID] ?? .idle
    }

    func isStored(_ itemID: Int) -> Bool {
        state(for: itemID) == .stored
    }

    /// The on-disk media file for an item, when it is stored — for local playback.
    func localURL(for itemID: Int) -> URL? {
        let url = Self.mediaURL(for: itemID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Actions

    /// Starts (or restarts) a download for an item.
    func download(_ item: MediaItem) {
        guard let api, let url = api.streamURL(itemID: item.id) else { return }
        guard state(for: item.id) != .stored else { return }

        var request = URLRequest(url: url)
        if let token = api.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.downloadTask(with: request)
        tasks[task.taskIdentifier] = item.id
        states[item.id] = .downloading(progress: 0)

        // Write the sidecar up front so a download in progress is still listed
        // and can be resumed/identified after a relaunch.
        writeSidecar(for: item)

        task.resume()
    }

    /// Removes a downloaded item from disk.
    func remove(_ itemID: Int) {
        try? FileManager.default.removeItem(at: Self.mediaURL(for: itemID))
        try? FileManager.default.removeItem(at: Self.sidecarURL(for: itemID))
        states[itemID] = .idle
        stored.removeAll { $0.id == itemID }
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

    static func sidecarURL(for itemID: Int) -> URL {
        directory.appendingPathComponent("\(itemID).json")
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

        for sidecar in entries where sidecar.pathExtension == "json" {
            guard let data = try? Data(contentsOf: sidecar),
                  let item = try? JSONDecoder().decode(DownloadedItem.self, from: data) else { continue }
            stored.append(item)
            // Stored only if the media file actually landed; a lone sidecar means
            // an interrupted download.
            states[item.id] = fm.fileExists(atPath: Self.mediaURL(for: item.id).path)
                ? .stored : .idle
        }
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

        Task { @MainActor in
            guard let itemID = tasks[identifier] else { try? FileManager.default.removeItem(at: temp); return }
            let dest = Self.mediaURL(for: itemID)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: temp, to: dest)
                states[itemID] = .stored
            } catch {
                states[itemID] = .failed
            }
            tasks[identifier] = nil
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
        Task { @MainActor in
            if let itemID = tasks[identifier] {
                states[itemID] = .failed
                tasks[identifier] = nil
            }
            _ = error
        }
    }
}
