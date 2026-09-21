// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import PDFKit
import SwiftUI

/// Reads a book — PDF now, EPUB to follow (S-161).
///
/// PDFs render with PDFKit (native, reliable) and resume to the saved page,
/// reporting the page back as a percent. EPUB needs unzipping a zip archive,
/// which the app has no dependency for yet; until that decision is made an EPUB
/// shows a clear "not yet" rather than a broken viewer.
struct ReaderView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    @State private var state: LoadState = .loading

    enum LoadState {
        case loading
        case pdf(document: PDFDocument, startPage: Int)
        case unsupported(format: String)
        case failed
    }

    var body: some View {
        ZStack {
            SoundChexTheme.base900.ignoresSafeArea()

            switch state {
            case .loading:
                ProgressView().tint(.white)

            case .pdf(let document, let startPage):
                PDFReader(document: document, startPage: startPage) { page, percent in
                    Task { try? await session.api?.saveReadingProgress(
                        itemID: item.id, location: String(page), percent: percent) }
                }
                .ignoresSafeArea(edges: .bottom)

            case .unsupported(let format):
                unavailable(
                    "\(format.uppercased()) isn't supported yet",
                    "Reading \(format.uppercased()) books in the app is coming. For now, open it in the web reader."
                )

            case .failed:
                unavailable("Couldn't open this book", "The file could not be loaded from the server.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }.foregroundStyle(SoundChexTheme.ink200)
            }
        }
        .task { await load() }
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "book.closed")
        } description: {
            Text(message)
        }
        .foregroundStyle(SoundChexTheme.ink300)
    }

    private func load() async {
        guard let api = session.api else { state = .failed; return }

        let info: APIClient.BookReader
        do {
            info = try await api.reader(itemID: item.id)
        } catch {
            state = .failed
            return
        }

        guard info.format == "pdf" else {
            state = .unsupported(format: info.format)
            return
        }

        // Load the file bytes with the bearer header (the reader route is
        // token-authed), then hand PDFKit the data.
        guard let url = api.bookURL(itemID: item.id) else { state = .failed; return }
        var request = URLRequest(url: url)
        if let token = api.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let document = PDFDocument(data: data) else {
            state = .failed
            return
        }

        // Resume: the saved location for a PDF is the page number.
        let startPage = Int(info.progress?.location ?? "") ?? 0
        state = .pdf(document: document, startPage: startPage)
    }
}

/// A UIKit `PDFView` bridged into SwiftUI, resuming to a page and reporting the
/// page (as a percent) as it turns.
private struct PDFReader: UIViewRepresentable {
    let document: PDFDocument
    let startPage: Int
    let onProgress: (Int, Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .black

        if startPage > 0, startPage < document.pageCount, let page = document.page(at: startPage) {
            view.go(to: page)
        }

        // Report the page as it changes.
        context.coordinator.observe(view, pageCount: document.pageCount, onProgress: onProgress)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observe(_ view: PDFView, pageCount: Int, onProgress: @escaping (Int, Int) -> Void) {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { _ in
                guard let current = view.currentPage,
                      let index = view.document?.index(for: current) else { return }
                let percent = pageCount > 1 ? Int(Double(index) / Double(pageCount - 1) * 100) : 100
                onProgress(index, percent)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
