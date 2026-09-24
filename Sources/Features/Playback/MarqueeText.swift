// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Text that scrolls itself when it is wider than the space it has (S-377).
///
/// A long title truncated to "The Road to Hell Is Highway 59 (feat…" hides the
/// part that tells you which track it is. Spotify and Apple Music both scroll
/// instead, so the whole title is readable without the row growing.
///
/// Scrolls only when it has to: text that fits is a plain `Text`, with no
/// animation running and nothing to distract. That matters here because the
/// now-playing page is on screen for the length of a record.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .primary
    /// The line height to reserve. A GeometryReader has no intrinsic height,
    /// so the row must be told how tall one line of this font is — passed in
    /// rather than guessed, since the title and the context line differ.
    var lineHeight: CGFloat
    /// How text that *fits* is placed. Only applies when it fits: text long
    /// enough to scroll always starts at the leading edge, or it would begin
    /// mid-word.
    var alignment: Alignment = .leading
    /// Seconds the text pauses at each end before travelling back.
    var pause: Double = 1.4
    /// Points travelled per second — slow enough to read at a glance.
    var speed: Double = 28

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    // Measured, not guessed: the decision to scroll depends on
                    // the rendered width, which varies with font and locale.
                    GeometryReader { text in
                        Color.clear
                            .onAppear { textWidth = text.size.width }
                            .onChange(of: text.size.width) { _, new in textWidth = new }
                    },
                )
                .offset(x: offset)
                .frame(width: proxy.size.width, alignment: overflow > 0 ? .leading : alignment)
                .clipped()
                .onAppear {
                    containerWidth = proxy.size.width
                    restart()
                }
                .onChange(of: proxy.size.width) { _, new in
                    containerWidth = new
                    restart()
                }
                // A new track is a new title: stop where we are and start the
                // new one from the left, rather than continuing mid-travel.
                .onChange(of: text) { _, _ in restart() }
                .onChange(of: overflow) { _, _ in restart() }
        }
        .frame(height: lineHeight)
    }

    private func restart() {
        offset = 0

        guard overflow > 0 else { return }

        let travel = Double(overflow) / speed

        withAnimation(
            .easeInOut(duration: travel)
                .delay(pause)
                .repeatForever(autoreverses: true),
        ) {
            offset = -overflow
        }
    }
}
