import SwiftUI

/// An image that caches to disk, so a cover is fetched once and then loads
/// instantly on every later scroll — and is available offline once seen.
///
/// `AsyncImage` keeps nothing across view lifetimes, so a music page of forty
/// covers re-requested all forty every time it appeared. This loads through a
/// shared `URLCache` (memory + disk), so a cover already seen comes from disk.
/// The loader is small and dependency-free.
struct CachedImage<Content: View, Placeholder: View>: View {
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

        if let image = await ImageCache.shared.image(for: url) {
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
            let (data, _) = try await session.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
