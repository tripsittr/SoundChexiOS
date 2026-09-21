// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// A horizontal, scrollable row of filter chips — the Music landing's sub-nav
/// (S-288, from the Spotify references).
///
/// One selection at a time (nil = "everything"). An inactive chip is a base-700
/// capsule with ink text; the active chip fills with `accent` and a round **×**
/// chip slides in on the left to clear it — the reference's "Albums ⊗" pattern,
/// with Spotify's green standing in as SoundChex red.
///
/// Generic over any `CaseIterable` label enum, so the same row drives the Music
/// landing today and any other chip filter later.
struct FilterChipRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    /// The visible label for an option.
    let label: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if selection != nil {
                    // The clear chip — a round × that resets to "everything".
                    Button {
                        withAnimation(SoundChexTheme.easeOut) { selection = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SoundChexTheme.ink100)
                            .frame(width: 34, height: 34)
                            .background(SoundChexTheme.base700, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ForEach(options, id: \.self) { option in
                    // When one is active, the others hide (matching the
                    // references: choosing "Albums" collapses the row to it).
                    if selection == nil || selection == option {
                        chip(option)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(SoundChexTheme.easeOut, value: selection)
        }
        .scrollClipDisabled()
    }

    private func chip(_ option: Option) -> some View {
        let active = selection == option
        return Button {
            withAnimation(SoundChexTheme.easeOut) {
                selection = active ? nil : option
            }
        } label: {
            Text(label(option))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .white : SoundChexTheme.ink100)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(active ? SoundChexTheme.accent : SoundChexTheme.base700, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
