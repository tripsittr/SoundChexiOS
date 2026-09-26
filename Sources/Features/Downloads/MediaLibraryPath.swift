// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import Foundation

/// Where a download lives so the Files app can find it (S-416).
///
/// Downloads used to sit in Application Support as `42.media` — invisible by
/// design and named by database id, which is right for a cache and wrong for
/// something the person owns. They now go under
/// `Documents/SoundChex/Media` in the same shape as the desktop library, so
/// the folder reads the same on a phone as it does on the server:
///
///     Music   Music/Artist/Album/## Track.ext
///     Movies  Movies/Title (Year)/Title (Year).ext
///     TV      TV/Show/Season 01/Show - S01E02.ext
///     Books   Books/Author/Title.ext
///
/// Mirrors `LibraryOrganizer::targetPath()` on the server deliberately. A
/// person with both should be able to copy a folder from one to the other
/// without rearranging anything.
enum MediaLibraryPath {
    /// The root the Files app shows. `Documents` is the only place iOS
    /// exposes, and only when the sharing keys are set in Info.plist.
    static let root: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let media = documents
            .appendingPathComponent("SoundChex", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)

        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

        // Kept excluded, as the old cache was. Documents is backed up by
        // default, and pushing a few hundred albums into someone's iCloud
        // allowance is not what downloading them meant.
        var url = media
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)

        return media
    }()

    /// The path for an item, relative to `root`, or nil when there is not
    /// enough metadata to place it. The caller falls back to a flat name
    /// rather than refusing the download.
    static func relativePath(for item: MediaItem, extension ext: String) -> String? {
        switch item.type {
        case .music: musicPath(item, ext)
        case .movie: moviePath(item, ext)
        case .show: showPath(item, ext)
        case .book: bookPath(item, ext)
        case .unknown: nil
        }
    }

    /// Music/Artist/Album/## Track.ext
    private static func musicPath(_ item: MediaItem, _ ext: String) -> String {
        let artist = safe(item.meta?.groupingArtist) ?? "Unknown Artist"
        let album = safe(item.meta?.album) ?? "Unknown Album"

        // Two digits, as the desktop does — so a folder sorts by track order
        // rather than lexically, where 10 comes before 2.
        let number = item.meta?.trackNumber.map { String(format: "%02d ", $0) } ?? ""

        return "Music/\(artist)/\(album)/\(number)\(safeName(item.title)).\(ext)"
    }

    /// Movies/Title (Year)/Title (Year).ext — the folder repeats the name
    /// because a film often travels with subtitles and artwork beside it.
    private static func moviePath(_ item: MediaItem, _ ext: String) -> String {
        let year = item.meta?.releaseYear.map { " (\($0))" } ?? ""
        let name = safeName(item.title) + year

        return "Movies/\(name)/\(name).\(ext)"
    }

    /// TV/Show/Season 01/Show - S01E02.ext
    private static func showPath(_ item: MediaItem, _ ext: String) -> String {
        // The series name, not the episode's own title.
        let show = safe(item.subtitle) ?? safeName(item.title)
        let season = item.meta?.seasonNumber ?? 1
        let episode = item.meta?.episodeNumber

        let code = episode.map { String(format: "S%02dE%02d", season, $0) }
            ?? safeName(item.title)

        return "TV/\(show)/\(String(format: "Season %02d", season))/\(show) - \(code).\(ext)"
    }

    /// Books/Author/Title.ext
    private static func bookPath(_ item: MediaItem, _ ext: String) -> String {
        let author = safe(item.meta?.author) ?? "Unknown Author"

        return "Books/\(author)/\(safeName(item.title)).\(ext)"
    }

    /// A path segment that will survive a filesystem and stay readable.
    ///
    /// Slashes are the dangerous ones — a track called "AC/DC" would
    /// otherwise silently become a directory. Colons too, which the Finder
    /// still shows as slashes.
    static func safeName(_ raw: String) -> String {
        var name = raw

        for bad in ["/", "\\", ":"] {
            name = name.replacingOccurrences(of: bad, with: "-")
        }

        // Control characters, and the leading dot that would hide the file.
        name = name.components(separatedBy: .controlCharacters).joined()
        name = name.trimmingCharacters(in: .whitespaces)

        while name.hasPrefix(".") {
            name.removeFirst()
        }

        // 255 bytes is the usual filename limit; leave room for an extension.
        if name.count > 180 {
            name = String(name.prefix(180)).trimmingCharacters(in: .whitespaces)
        }

        return name.isEmpty ? "Untitled" : name
    }

    private static func safe(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        return safeName(raw)
    }

    /// Makes the folders for a relative path and returns the full URL.
    static func prepare(_ relativePath: String) -> URL {
        let url = root.appendingPathComponent(relativePath)

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        return url
    }
}
