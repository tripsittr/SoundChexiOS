// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// An image that caches to disk, so a cover is fetched once and then loads
/// instantly on every later scroll — and is available offline once seen.
///
/// `AsyncImage` keeps nothing across view lifetimes, so a music page of forty
/// covers re-requested all forty every time it appeared. This loads through a
/// shared `URLCache` (memory + disk), so a cover already seen comes from disk.
/// The loader is small and dependency-free.
struct CachedImage<Content: View, Placeholder: View>: View {
    @Environment(Session.self) private var session

    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        uiImage = nil
        guard let url else { return }

        // Point the URL at the server this device can currently reach. A
        // download's sidecar freezes whichever address the server answered on
        // when the file was fetched, and that address does not work from
        // everywhere — a cover saved at home pointed at the tailnet host and
        // vanished the moment the phone left the tailnet (S-329). Done here
        // rather than at each of the eleven call sites, so nothing can be
        // missed and new callers inherit it.
        let resolved = ArtworkURL.rebased(url, onto: session.serverURL)

        if let image = await ImageCache.shared.image(for: resolved) {
            uiImage = image
        }
    }
}

/// A shared image cache over a disk-backed URLCache.
actor ImageCache {
    static let shared = ImageCache()

    private let session: URLSession

    init() {
        let cache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,   // 32 MB in memory
            diskCapacity: 512 * 1024 * 1024,    // 512 MB on disk
            diskPath: "soundchex-artwork"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// The decoded image for a URL, from cache when present. Nil on failure.
    func image(for url: URL) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: url)

            // A 404 still carries a body, and URLCache will happily keep it —
            // so a cover that failed once stayed "cached" as an error page and
            // never recovered, even after the real image became reachable
            // (S-329). Refuse the response and evict anything stored for it.
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                session.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))

                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
