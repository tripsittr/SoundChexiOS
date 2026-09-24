// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI
import UIKit

/// Lays a book out into fixed, screen-sized pages for the Kindle-style reader
/// (S-304).
///
/// The server delivers the book as chapters of reflowable text; a chapter may be
/// a paragraph or forty pages. This breaks each chapter's text into pages that
/// exactly fill the reading area for the current font and page size, using
/// TextKit's line layout so a page never cuts a line in half. A chapter's title
/// sits on its first page; its images follow its text as their own pages, so an
/// illustration or a scanned page gets a full page of its own.
///
/// Re-run whenever the font size or the page size changes (a rotation, a Dynamic
/// Type change) — pagination is a function of both.
enum BookPaginator {
    /// One laid-out page of the book.
    struct Page: Identifiable, Equatable {
        let id = UUID()
        /// The chapter this page belongs to, for the "where am I" line and resume.
        let chapterPosition: Int
        /// The source page number (PDF), for display; nil for EPUB.
        let sourcePage: Int?
        /// A chapter heading, shown only on the chapter's first text page.
        let title: String?
        /// The slice of the chapter's text on this page (empty for an image page).
        let text: String
        /// An image that is the whole of this page (a plate, a scanned page).
        let image: APIClient.BookContent.Image?

        static func == (lhs: Page, rhs: Page) -> Bool { lhs.id == rhs.id }
    }

    /// Paginate the whole book for a given reading area and settings.
    ///
    /// `size` is the text area (already inset from the screen edges). Returns at
    /// least one page so the reader always has something to show.
    static func paginate(
        chapters: [APIClient.BookContent.Chapter],
        imagesByPage: [Int: [APIClient.BookContent.Image]],
        size: CGSize,
        settings: ReaderSettings
    ) -> [Page] {
        guard size.width > 20, size.height > 20 else {
            // No usable area yet (first layout pass) — a single placeholder page
            // keeps the view valid until a real size arrives and we re-run.
            return [Page(chapterPosition: chapters.first?.position ?? 1,
                         sourcePage: chapters.first?.page, title: chapters.first?.title,
                         text: chapters.first?.text ?? "", image: nil)]
        }

        var pages: [Page] = []

        for chapter in chapters {
            let key = chapter.page ?? chapter.position
            let images = imagesByPage[key] ?? []

            let textPages = splitText(
                chapter.text, title: chapter.title, size: size, settings: settings)

            for (index, slice) in textPages.enumerated() {
                pages.append(Page(
                    chapterPosition: chapter.position,
                    sourcePage: chapter.page,
                    // The heading belongs on the first page of the chapter only.
                    title: index == 0 ? chapter.title : nil,
                    text: slice,
                    image: nil))
            }

            // Each image its own page, after the chapter's text.
            for image in images {
                pages.append(Page(
                    chapterPosition: chapter.position,
                    sourcePage: chapter.page,
                    title: textPages.isEmpty ? chapter.title : nil,
                    text: "",
                    image: image))
            }
        }

        return pages.isEmpty
            ? [Page(chapterPosition: 1, sourcePage: nil, title: nil, text: "", image: nil)]
            : pages
    }

    /// Break one chapter's text into page-sized slices using TextKit line layout.
    ///
    /// The title, when present, takes space on the first page, so the first slice
    /// gets a smaller text area — otherwise the heading would push the last line
    /// off the page.
    private static func splitText(
        _ text: String, title: String?, size: CGSize, settings: ReaderSettings
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        let font = bodyFont(settings)
        let paragraphStyle = NSMutableParagraphStyle()
        // Match the on-screen line spacing (SwiftUI lineSpacing is additive).
        paragraphStyle.lineSpacing = settings.fontSize * 0.4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let storage = NSTextStorage(string: trimmed, attributes: attributes)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        // The height a chapter title consumes on the first page (heading + gap).
        let titleHeight = title.map { _ in (settings.fontSize + 4) * 1.3 + 16 } ?? 0

        var slices: [String] = []
        var glyphIndex = 0
        var isFirstPage = true
        let ns = trimmed as NSString

        // Guard against a pathological zero-progress loop.
        var safety = 0
        let maxPages = 5000

        while glyphIndex < layoutManager.numberOfGlyphs, safety < maxPages {
            safety += 1

            let pageHeight = size.height - (isFirstPage ? titleHeight : 0)
            let container = NSTextContainer(size: CGSize(width: size.width, height: max(pageHeight, 40)))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let range = layoutManager.glyphRange(for: container)
            if range.length == 0 { break }

            let charRange = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            slices.append(ns.substring(with: charRange).trimmingCharacters(in: .whitespacesAndNewlines))

            glyphIndex = NSMaxRange(range)
            isFirstPage = false
        }

        return slices.filter { !$0.isEmpty }
    }

    private static func bodyFont(_ settings: ReaderSettings) -> UIFont {
        let base = UIFont.systemFont(ofSize: settings.fontSize)
        guard settings.serif,
              let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: settings.fontSize)
    }
}
