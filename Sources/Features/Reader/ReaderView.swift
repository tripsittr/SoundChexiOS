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
            ReaderScroll(chapters: chapters, images: images, token: session.api?.token,
                         settings: settings, startChapter: startChapter) { position in
                let percent = chapters.isEmpty ? 0
                    : Int(Double(position - 1) / Double(max(chapters.count - 1, 1)) * 100)
                Task {
                    try? await session.api?.saveReadingProgress(
                        itemID: item.id, location: String(position), percent: percent)
                }
            }

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
    let onReachChapter: (Int) -> Void

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
                            // plate, a diagram) — the text-and-images read.
                            ForEach(imagesByPage[chapter.position] ?? []) { image in
                                ReaderImage(image: image, token: token)
                            }
                        }
                        .id(chapter.position)
                        .onAppear {
                            if chapter.position != reported {
                                reported = chapter.position
                                onReachChapter(chapter.position)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if startChapter > 1 {
                    proxy.scrollTo(startChapter, anchor: .top)
                }
            }
        }
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
