// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Text that scrolls itself when it is wider than the space it has (S-377).
///
/// A long title truncated to "The Road to Hell Is Highway 59 (feat…" hides the
/// part that tells you which track it is. Spotify and Apple Music both scroll
/// instead, so the whole title is readable without the row growing.
///
/// The cycle is: hold at the start, travel one way until the text has fully
/// passed, hold again, repeat. It never turns round (S-378) — a second copy
/// follows the first, and when the first has gone the offset resets to zero.
/// The copies are identical, so the reset is invisible and it reads as a
/// revolving door.
///
/// The rests matter (S-379): without them the title is always moving and never
/// settles long enough to read at a glance. `repeatForever` cannot express a
/// hold, so the phases are driven by a task — which also gives a clean way to
/// stop, since a track change must not leave the old cycle running.
///
/// Scrolls only when it has to: text that fits is a plain `Text`, with no
/// animation and no task. That matters because the now-playing page is on
/// screen for the length of a record.
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
    /// How long the text rests at each end of a revolution.
    var pause: Double = 1.8
    /// How much faster the wrap-around leg runs than the reading leg.
    ///
    /// That leg carries the tail of the title off and brings the next copy in;
    /// there is nothing to read during it, and at reading speed it is by far
    /// the longest part of the cycle — the title would spend most of its time
    /// off screen.
    var wrapSpeedFactor: Double = 2.6

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var scrolls: Bool { textWidth > containerWidth && containerWidth > 0 }

    /// How far the first copy travels before the second sits exactly where it
    /// started — one full turn of the door.
    private var travel: CGFloat { textWidth + gap }

    /// How far the text must move for its last word to reach the trailing
    /// edge — where the cycle rests before carrying on round.
    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

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
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, new in containerWidth = new }
        }
        .frame(height: lineHeight)
        // Keyed on everything the cycle depends on, so a track change, a
        // re-measure or a rotation tears the old task down and starts a fresh
        // one rather than leaving two driving the same offset.
        .task(id: cycleKey) { await run() }
    }

    /// Identity of the current cycle. A change to any of these invalidates the
    /// running task.
    private var cycleKey: String {
        "\(text)|\(textWidth)|\(containerWidth)"
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
    /// so a second reader would report the same number and restart the cycle
    /// for nothing.
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

    /// Hold at the start, scroll to the end, hold there, then carry on round.
    ///
    /// Two legs rather than one, because the rest the user asked for is at the
    /// *end of the title* — the point where the last word is on screen — not
    /// at the end of the travel, where the text has already gone and a pause
    /// would just be a blank gap sitting still.
    private func run() async {
        // A new cycle always starts from the left, however far the last one
        // had got. Unanimated, so it does not slide back visibly.
        offset = 0

        guard scrolls else { return }

        // Leg one: until the end of the text meets the trailing edge.
        let toEnd = overflow
        // Leg two: the rest of the turn, taking the first copy off and
        // bringing the second into its place.
        let toWrap = travel - overflow

        while !Task.isCancelled {
            // Rest at the start, so the opening of the title can be read.
            guard await sleep(pause) else { return }

            withAnimation(.linear(duration: Double(toEnd) / speed)) { offset = -toEnd }

            guard await sleep(Double(toEnd) / speed) else { return }

            // Rest again with the end of the title on screen.
            guard await sleep(pause) else { return }

            let wrapDuration = Double(toWrap) / (speed * wrapSpeedFactor)

            withAnimation(.linear(duration: wrapDuration)) { offset = -travel }

            guard await sleep(wrapDuration) else { return }

            // The second copy now sits exactly where the first began, so
            // snapping back to zero shows no change at all.
            offset = 0
        }
    }

    /// Sleeps, reporting whether it finished rather than being cancelled — so
    /// a cancelled cycle stops without animating anything further.
    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))

            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
