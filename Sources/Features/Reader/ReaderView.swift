// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A paginated, Kindle-style book reader (S-295, S-304).
///
/// The server parses the book (PDF text, scanned-page OCR, or EPUB chapters) and
/// serves it as ordered text; this lays the text out into fixed, screen-sized
/// pages and turns them one at a time — tap the right side or swipe left for the
/// next page, the left side or swipe right for the previous, the centre to show
/// or hide the bars. The same reader works for every format because the device
/// renders the parsed text itself.
///
/// Resume is by chapter: the saved location is the chapter position, and opening
/// the book jumps to that chapter's first page. Progress is reported as it reads.
struct ReaderView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    @State private var chapters: [APIClient.BookContent.Chapter] = []
    @State private var images: [APIClient.BookContent.Image] = []
    @State private var phase: Phase = .loading
    @State private var settings = ReaderSettings.load()
    @State private var showingSettings = false
    @State private var startChapter = 1

    /// The laid-out pages and where we are in them.
    @State private var pages: [BookPaginator.Page] = []
    @State private var pageIndex = 0
    /// The area the last pagination was computed for, so we only re-paginate when
    /// the size or the settings actually change.
    @State private var paginatedFor: CGSize = .zero
    /// The reader chrome (bars) — hidden by default for an immersive read, toggled
    /// by a centre tap.
    @State private var chromeVisible = true

    enum Phase { case loading, processing, ready, empty, failed }

    private var imagesByPage: [Int: [APIClient.BookContent.Image]] {
        Dictionary(grouping: images, by: \.page)
    }

    var body: some View {
        NavigationStack {
            content
                .background(settings.theme.background)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(1)
                                .foregroundStyle(settings.theme.text)
                            if phase == .ready {
                                Text(locationSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(settings.theme.text.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingSettings.toggle() } label: {
                            Image(systemName: "textformat.size")
                        }
                        .disabled(phase != .ready)
                    }
                }
                .toolbarBackground(settings.theme.background, for: .navigationBar)
                .tint(settings.theme.tint)
                .sheet(isPresented: $showingSettings) {
                    ReaderSettingsSheet(settings: $settings)
                        .presentationDetents([.height(220)])
                }
        }
        .statusBarHidden(!chromeVisible)
        .task { await load() }
    }

    /// "Page 42 · Chapter 3: Don't Try · 18%" — only the parts that exist for this
    /// book: EPUB has no page number, so it shows the chapter; the percentage is
    /// how far through the laid-out pages we are.
    private var locationSubtitle: String {
        var parts: [String] = []
        if let page = pages[safe: pageIndex]?.sourcePage {
            parts.append("Page \(page)")
        }
        if let chapter = effectiveChapterTitle {
            parts.append(chapter)
        }
        parts.append("\(percent)%")
        return parts.joined(separator: " · ")
    }

    /// How far through the book, by page count.
    private var percent: Int {
        guard pages.count > 1 else { return pages.isEmpty ? 0 : 100 }
        return Int(Double(pageIndex) / Double(pages.count - 1) * 100)
    }

    /// The chapter title in effect at the current page — the nearest heading at or
    /// before this page's chapter, so a page mid-chapter still names its chapter.
    private var effectiveChapterTitle: String? {
        guard let position = pages[safe: pageIndex]?.chapterPosition else { return nil }
        return chapters
            .prefix(while: { $0.position <= position })
            .last(where: { !($0.title ?? "").isEmpty })?
            .title
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading, .processing:
            VStack(spacing: 12) {
                ProgressView().tint(settings.theme.text)
                Text(phase == .processing ? "Preparing this book…" : "Loading…")
                    .font(.footnote).foregroundStyle(settings.theme.text.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            GeometryReader { geo in
                let insets = EdgeInsets(top: 24, leading: 26, bottom: 40, trailing: 26)
                let area = CGSize(
                    width: geo.size.width - insets.leading - insets.trailing,
                    height: geo.size.height - insets.top - insets.bottom)

                ReaderPager(
                    pages: pages, token: session.api?.token, settings: settings,
                    insets: insets, pageIndex: $pageIndex,
                    onTurn: { onPageChanged() },
                    onToggleChrome: { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } }
                )
                // Lay out (and re-lay out) whenever the area or the settings change.
                .task(id: PaginationKey(size: area, settings: settings)) {
                    repaginate(area: area)
                }
            }

        case .empty:
            unavailable("Nothing to read", "This book has no text the reader could extract.")

        case .failed:
            unavailable("Couldn't open this book", "The book could not be loaded from the server.")
        }
    }

    /// Re-lay the book into pages for a reading area, keeping the reader roughly
    /// where it was (by the chapter it was on) across a font-size or size change.
    private func repaginate(area: CGSize) {
        let anchorChapter = pages[safe: pageIndex]?.chapterPosition ?? startChapter

        let laidOut = BookPaginator.paginate(
            chapters: chapters, imagesByPage: imagesByPage, size: area, settings: settings)

        pages = laidOut
        paginatedFor = area

        // Land on the first page of the chapter we were reading (or resuming to).
        if let idx = laidOut.firstIndex(where: { $0.chapterPosition >= anchorChapter }) {
            pageIndex = idx
        } else {
            pageIndex = min(pageIndex, max(laidOut.count - 1, 0))
        }
    }

    private func onPageChanged() {
        saveProgress()
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "book.closed")
        } description: {
            Text(message)
        }
    }

    private func load() async {
        guard let api = session.api else { phase = .failed; return }

        // Where to resume — the chapter position saved last time.
        if let info = try? await api.reader(itemID: item.id),
           let location = info.progress?.location, let position = Int(location) {
            startChapter = position
        }

        // Poll while the server extracts; a scanned book takes a moment.
        for attempt in 0 ..< 30 {
            guard let result = try? await api.readerContent(itemID: item.id) else {
                phase = .failed
                return
            }

            switch result.status {
            case "ready":
                chapters = result.chapters ?? []
                images = result.images ?? []
                phase = chapters.isEmpty ? .empty : .ready
                return
            case "empty":
                phase = .empty
                return
            case "processing":
                phase = .processing
                try? await Task.sleep(for: .seconds(attempt < 5 ? 1 : 3))
            default:
                phase = .failed
                return
            }
        }

        // Gave up waiting — leave it processing so a re-open tries again.
        phase = .processing
    }

    /// Saves the reading place — the current page's chapter (to resume to) and the
    /// page-based percentage (to display). The server keeps the furthest point.
    private func saveProgress() {
        guard let position = pages[safe: pageIndex]?.chapterPosition else { return }
        let percent = self.percent
        Task {
            try? await session.api?.saveReadingProgress(
                itemID: item.id, location: String(position), percent: percent)
        }
    }
}

/// A key that changes when either the reading area or the settings change, so the
/// pager re-paginates exactly then and no more often.
private struct PaginationKey: Equatable {
    let size: CGSize
    let settings: ReaderSettings
}

/// The paged book: one full page at a time, turned by tap zones (left/right
/// thirds) and swipes, with the centre tapping the bars on and off.
private struct ReaderPager: View {
    let pages: [BookPaginator.Page]
    let token: String?
    let settings: ReaderSettings
    let insets: EdgeInsets
    @Binding var pageIndex: Int
    let onTurn: () -> Void
    let onToggleChrome: () -> Void

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            TabView(selection: $pageIndex) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ReaderPageView(page: page, token: token, settings: settings, insets: insets)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: pageIndex) { _, _ in onTurn() }

            // Tap zones sit above the pages: left third = back, right third =
            // forward, centre = toggle the bars. Swiping still works because the
            // zones only claim taps, and the TabView handles the drag underneath.
            HStack(spacing: 0) {
                tapZone { turn(by: -1) }
                tapZone { onToggleChrome() }
                tapZone { turn(by: 1) }
            }
        }
    }

    private func tapZone(_ action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture { action() }
    }

    private func turn(by delta: Int) {
        let next = pageIndex + delta
        guard next >= 0, next < pages.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) { pageIndex = next }
    }
}

/// One laid-out page: an optional chapter heading, the page's text, or a
/// full-page image.
private struct ReaderPageView: View {
    let page: BookPaginator.Page
    let token: String?
    let settings: ReaderSettings
    let insets: EdgeInsets

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = page.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: settings.fontSize + 4, weight: .bold,
                                  design: settings.serif ? .serif : .default))
                    .foregroundStyle(settings.theme.text)
            }

            if let image = page.image {
                Spacer(minLength: 0)
                ReaderImage(image: image, token: token)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if !page.text.isEmpty {
                Text(page.text)
                    .font(.system(size: settings.fontSize, design: settings.serif ? .serif : .default))
                    .foregroundStyle(settings.theme.text)
                    .lineSpacing(settings.fontSize * 0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(insets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One inline book image, loaded with the bearer header (the asset route is
/// token-authed), sized to the page.
private struct ReaderImage: View {
    let image: APIClient.BookContent.Image
    let token: String?

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.15))
                    .aspectRatio(image.aspect, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
        .task(id: image.url) { await load() }
    }

    private func load() async {
        var request = URLRequest(url: image.url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let loaded = UIImage(data: data) {
            uiImage = loaded
        }
    }
}

private extension APIClient.BookContent.Image {
    /// A placeholder aspect ratio while loading, from the known dimensions.
    var aspect: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 0.7 }
        return CGFloat(width) / CGFloat(height)
    }
}

private extension Array {
    /// Safe indexed access — nil rather than a crash when the index is stale
    /// (e.g. mid-repagination).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
