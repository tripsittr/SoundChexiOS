// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The three-bar "now playing" equalizer that marks the current track in a list
/// (S-288, from the Spotify references).
///
/// It sits where a row's number or art thumbnail would be. When the track is
/// actually playing the bars animate; when it is the current track but paused,
/// they hold at rest. Respects Reduce Motion — a static accent bar icon stands in
/// for the animation, so the "this is the one" signal survives without movement.
struct PlayingEqualizer: View {
    /// Whether audio is advancing. Paused shows the bars at rest, not animating.
    var isAnimating: Bool = true

    var color: Color = SoundChexTheme.accent
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Each bar animates on its own phase so they don't move in lockstep.
    private let bars = 3
    private let phases: [Double] = [0, 0.25, 0.5]

    var body: some View {
        if reduceMotion {
            // A steady mark rather than motion — still clearly "the active one".
            Image(systemName: "waveform")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isAnimating)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: size * 0.09) {
                    ForEach(0..<bars, id: \.self) { i in
                        Capsule()
                            .fill(color)
                            .frame(width: size * 0.13, height: barHeight(t: t, phase: phases[i]))
                    }
                }
                .frame(width: size, height: size, alignment: .center)
            }
        }
    }

    /// A bar's height as a smooth oscillation between ~25% and ~90% of the box.
    /// When not animating the timeline is frozen, so this returns a stable
    /// resting height per bar.
    private func barHeight(t: Double, phase: Double) -> CGFloat {
        let low = size * 0.25
        let high = size * 0.9
        let wave = isAnimating
            ? (sin((t * 3.2) + (phase * .pi * 2)) + 1) / 2   // 0…1
            : 0.4                                            // resting
        return low + (high - low) * wave
    }
}
