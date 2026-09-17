import Foundation
import Observation

/// The device's copy of the catalogue, loaded once and filtered by every screen.
///
/// One fetch of `/api/v1/library` fills this; the tabs read from it rather than
/// each hitting the network. A later milestone persists it for offline and keeps
/// it in step with `/library/delta`, the way the web mirror does.
@MainActor
@Observable
final class LibraryStore {
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private var api: APIClient?
    private var hasLoaded = false

    func attach(api: APIClient?) {
        self.api = api
    }

    /// Loads the catalogue the first time a tab appears. Repeated calls are cheap
    /// no-ops, so every tab's `.task` can call it without re-fetching.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func load() async {
        guard let api else { return }

        isLoading = true
        loadError = nil

        do {
            let response = try await api.library()
            items = response.items
            hasLoaded = true
        } catch {
            loadError = (error as? APIClient.APIError)?.errorDescription
                ?? "Could not load your library."
        }

        isLoading = false
    }

    // MARK: - Filtered views

    func items(of type: MediaType) -> [MediaItem] {
        items
            .filter { $0.type == type }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Top-level items of a type — for shows and albums we don't want every
    /// episode/track in the grid, only the parents. An item with no `parentID`
    /// is a top-level one.
    func topLevel(of type: MediaType) -> [MediaItem] {
        items(of: type).filter { $0.parentID == nil }
    }

    // MARK: - Home

    /// The hero item — the most recently added top-level thing with artwork.
    var heroItem: MediaItem? {
        items
            .filter { $0.parentID == nil && $0.artwork != nil }
            .first
    }

    /// The home rails: a "Recently added" mix, then one row per type. Derived
    /// from the loaded catalogue, the way the web home composes its rows.
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let items: [MediaItem]
    }

    var homeRows: [Row] {
        var rows: [Row] = []

        let recent = items.filter { $0.parentID == nil }.prefix(20)
        if !recent.isEmpty { rows.append(Row(title: "Recently added", items: Array(recent))) }

        for (type, label) in [(MediaType.music, "Music"), (.movie, "Movies"),
                              (.show, "Shows"), (.book, "Books")] {
            let ofType = topLevel(of: type).prefix(20)
            if !ofType.isEmpty { rows.append(Row(title: label, items: Array(ofType))) }
        }

        return rows
    }

    func search(_ term: String) -> [MediaItem] {
        let needle = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }

        return items.filter { item in
            item.title.lowercased().contains(needle)
                || (item.subtitle?.lowercased().contains(needle) ?? false)
                || (item.meta?.artist?.lowercased().contains(needle) ?? false)
                || (item.meta?.album?.lowercased().contains(needle) ?? false)
                || (item.meta?.author?.lowercased().contains(needle) ?? false)
        }
    }
}
