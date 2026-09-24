// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Text that scrolls itself when it is wider than the space it has (S-377).
///
/// A long title truncated to "The Road to Hell Is Highway 59 (feat…" hides the
/// part that tells you which track it is. Spotify and Apple Music both scroll
/// instead, so the whole title is readable without the row growing.
///
/// It travels one way and never turns round (S-378). The first version ran to
/// the end and eased back, and the reversal caught the eye every time — the
/// motion itself became the thing you noticed. Here a second copy of the text
/// follows the first, and when the first has gone the offset resets to zero;
/// the copies are identical, so the jump is invisible and the text reads as a
/// revolving door. Linear timing, because a constant speed is what makes it
/// disappear into the background.
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
    /// Points travelled per second — slow enough to read at a glance.
    var speed: Double = 30
    /// The gap between the end of one copy and the start of the next, so the
    /// title does not run straight into itself.
    var gap: CGFloat = 44

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var scrolls: Bool { textWidth > containerWidth && containerWidth > 0 }

    /// How far the first copy travels before the second sits exactly where it
    /// started — one full turn of the door.
    private var travel: CGFloat { textWidth + gap }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if scrolls {
                    HStack(spacing: gap) {
                        measuredLabel
                        // The copy that follows the first in. Hidden from
                        // VoiceOver, which should hear the title once.
                        label.accessibilityHidden(true)
                    }
                    .offset(x: offset)
                    .frame(width: proxy.size.width, alignment: .leading)
                } else {
                    measuredLabel
                        .frame(width: proxy.size.width, alignment: alignment)
                }
            }
            .clipped()
            .onAppear {
                containerWidth = proxy.size.width
                restart()
            }
            .onChange(of: proxy.size.width) { _, new in
                containerWidth = new
                restart()
            }
            // A new track is a new title: start it from the left rather than
            // continuing wherever the old one had got to.
            .onChange(of: text) { _, _ in restart() }
            .onChange(of: textWidth) { _, _ in restart() }
        }
        .frame(height: lineHeight)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// The first copy, carrying the width measurement.
    ///
    /// Only this one measures: both copies are the same text at the same font,
    /// so a second reader would report the same number and set the same state,
    /// restarting the animation for nothing.
    private var measuredLabel: some View {
        label.background(
            // Measured, not guessed: whether to scroll depends on the rendered
            // width, which varies with font and locale.
            GeometryReader { text in
                Color.clear
                    .onAppear { textWidth = text.size.width }
                    .onChange(of: text.size.width) { _, new in textWidth = new }
            },
        )
    }

    private func restart() {
        // Cancel whatever is running before re-measuring, or the old animation
        // keeps driving the offset and the two fight each other.
        withAnimation(.linear(duration: 0)) { offset = 0 }

        guard scrolls else { return }

        withAnimation(.linear(duration: Double(travel) / speed).repeatForever(autoreverses: false)) {
            offset = -travel
        }
    }
}
