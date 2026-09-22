// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A reflowable, Kindle-style book reader (S-295).
///
/// The server parses the book (PDF text, scanned-page OCR, or EPUB chapters) and
/// serves it as ordered text; this renders it as one continuous, resizable read
/// with an adjustable font size and page theme. The same reader works for every
/// format because the device never touches the file — it reads the parsed text.
///
/// Resume is by chapter: the saved location is the chapter position, and opening
/// the book scrolls to it. Progress is reported back as it is read.
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

    /// Where the reader is right now, tracked as they scroll so the top shows the
    /// page and chapter and a live reading percentage.
    @State private var currentChapter: APIClient.BookContent.Chapter?
    @State private var percent = 0

    enum Phase { case loading, processing, ready, empty, failed }

    var body: some View {
        NavigationStack {
            content
                .background(settings.theme.background)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    // The place in the book: page and chapter, with the reading
                    // percentage — the reader's "where am I" line, under the title.
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
        .task { await load() }
    }

    /// "Page 42 · Chapter 3: Don't Try · 18%" — only the parts that exist for
    /// this book: EPUB has no page number, so it shows the chapter; the chapter
    /// carries forward from the last heading so a page mid-chapter still names it.
    private var locationSubtitle: String {
        var parts: [String] = []
        if let page = currentChapter?.page {
            parts.append("Page \(page)")
        }
        if let chapter = effectiveChapterTitle {
            parts.append(chapter)
        }
        parts.append("\(percent)%")
        return parts.joined(separator: " · ")
    }

    /// A coarse percentage from a chapter's position — the iOS 17 fallback when
    /// live scroll geometry isn't available.
    private func chapterPercent(for chapter: APIClient.BookContent.Chapter) -> Int {
        guard chapters.count > 1,
              let index = chapters.firstIndex(where: { $0.position == chapter.position })
        else { return 0 }
        return Int(Double(index) / Double(chapters.count - 1) * 100)
    }

    /// The chapter title in effect at the current position — the nearest heading
    /// at or before it, so it persists through the pages of that chapter.
    private var effectiveChapterTitle: String? {
        guard let position = currentChapter?.position else { return nil }
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
            ReaderScroll(
                chapters: chapters, images: images, token: session.api?.token,
                settings: settings, startChapter: startChapter,
                onReachChapter: { chapter in
                    currentChapter = chapter
                    // On iOS 17 (no scroll geometry) this is the percentage; on 18+
                    // the smoother scroll value below takes over.
                    if #unavailable(iOS 18.0) {
                        percent = chapterPercent(for: chapter)
                    }
                    saveProgress()
                },
                onScrollPercent: { percent = $0 }
            )

        case .empty:
            unavailable("Nothing to read", "This book has no text the reader could extract.")

        case .failed:
            unavailable("Couldn't open this book", "The book could not be loaded from the server.")
        }
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
                // Back off a little between polls.
                try? await Task.sleep(for: .seconds(attempt < 5 ? 1 : 3))
            default:
                phase = .failed
                return
            }
        }

        // Gave up waiting — leave it processing so a re-open tries again.
        phase = .processing
    }

    /// Saves the reading place — the current chapter position (to resume to) and
    /// the scroll percentage (to display). Called as chapters scroll by; the
    /// server keeps the furthest point, so an occasional out-of-order save is
    /// harmless.
    private func saveProgress() {
        guard let position = currentChapter?.position else { return }
        let percent = self.percent
        Task {
            try? await session.api?.saveReadingProgress(
                itemID: item.id, location: String(position), percent: percent)
        }
    }
}

/// The scrolling text, chapter by chapter, with each page's images placed inline
/// after its text — so an illustrated or scanned book reads with its pictures,
/// the same as the desktop reader. Resumes to a chapter and reports the one that
/// scrolls into view.
private struct ReaderScroll: View {
    let chapters: [APIClient.BookContent.Chapter]
    let images: [APIClient.BookContent.Image]
    let token: String?
    let settings: ReaderSettings
    let startChapter: Int
    /// The chapter/page scrolled into view, for the "where am I" line and resume.
    let onReachChapter: (APIClient.BookContent.Chapter) -> Void
    /// How far through the whole book the reader has scrolled, 0–100, updated
    /// continuously as they read (not just at chapter boundaries).
    let onScrollPercent: (Int) -> Void

    @State private var reported = 0

    /// Images grouped by the page they belong on, for O(1) lookup per chapter.
    private var imagesByPage: [Int: [APIClient.BookContent.Image]] {
        Dictionary(grouping: images, by: \.page)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(chapters) { chapter in
                        VStack(alignment: .leading, spacing: 16) {
                            if let title = chapter.title, !title.isEmpty {
                                Text(title)
                                    .font(.system(size: settings.fontSize + 4, weight: .bold, design: settings.serif ? .serif : .default))
                                    .foregroundStyle(settings.theme.text)
                            }
                            if !chapter.text.isEmpty {
                                Text(chapter.text)
                                    .font(.system(size: settings.fontSize, design: settings.serif ? .serif : .default))
                                    .foregroundStyle(settings.theme.text)
                                    .lineSpacing(settings.fontSize * 0.4)
                            }
                            // The page's images, inline (a scanned page's image, a
                            // plate, a diagram) — the text-and-images read. Images
                            // are keyed by source page, so match on the chapter's
                            // page; position is reading order and can differ from
                            // the page once blank pages are dropped.
                            ForEach(imagesByPage[chapter.page ?? chapter.position] ?? []) { image in
                                ReaderImage(image: image, token: token)
                            }
                        }
                        .id(chapter.position)
                        .onAppear {
                            if chapter.position != reported {
                                reported = chapter.position
                                onReachChapter(chapter)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            // A continuous read-through percentage from the scroll offset: how far
            // the content has moved past the top over its total scrollable height.
            // Smoother and more honest than "chapter N of M", which jumps.
            // iOS 18+ has scroll geometry; on 17 we fall back to chapter progress
            // (reported from onReachChapter), so the percentage still moves.
            .modifier(ScrollPercentTracker(onScrollPercent: onScrollPercent))
            .onAppear {
                if startChapter > 1 {
                    proxy.scrollTo(startChapter, anchor: .top)
                }
            }
        }
    }
}

/// Reports a 0–100 read-through percentage from live scroll geometry where the
/// OS supports it (iOS 18+); on iOS 17 it is a no-op and the reader falls back to
/// chapter-based progress.
private struct ScrollPercentTracker: ViewModifier {
    let onScrollPercent: (Int) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Int.self) { geometry in
                let scrollable = geometry.contentSize.height - geometry.containerSize.height
                guard scrollable > 0 else { return 0 }
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return Int((offset / scrollable * 100).rounded().clamped(to: 0 ... 100))
            } action: { _, percent in
                onScrollPercent(percent)
            }
        } else {
            content
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// One inline book image, loaded with the bearer header (the asset route is
/// token-authed), sized to the reading column.
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
