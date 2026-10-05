// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The web app's bottom bar, drawn rather than configured (S-449).
///
/// Two earlier attempts set `UITabBarAppearance` — the fill, the hairline, a
/// selection indicator — and the bar still looked like iOS. On iOS 26 the
/// system tab bar is a **floating rounded capsule, inset from the screen
/// edges**, and no appearance property changes that: the shape is the
/// platform's, not the app's. The web bar is the opposite shape —
///
///     position: fixed; inset-inline: 0; bottom: 0;
///     background: color-mix(in srgb, var(--color-base-800) 94%, transparent);
///     border-top: 1px solid var(--color-base-600);
///
/// — full width, square corners, flush to the bottom, with a hairline across
/// the whole top edge. A capsule cannot be made into that, so this draws the
/// bar instead of asking UIKit for one.
///
/// Everything here is the stylesheet's own numbers rather than an
/// approximation: `.mobile-tab` is a 3.25rem minimum height with a 1.375rem
/// icon and a 0.625rem label, and the active tab carries a 1.75rem × 2px
/// accent bar on its **top** edge — where the eye already is after the icon,
/// and clear of the home indicator.
struct MediaTabBar: View {
    @Environment(ThemeStore.self) private var theme

    @Binding var selection: MediaTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MediaTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    tabContent(tab)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        // `grid-auto-columns: 1fr` — every tab the same width, however many
        // there are.
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                SoundChexTheme.base800.opacity(0.94)

                // The hairline across the full width, which is the single
                // clearest difference from the floating capsule.
                Rectangle()
                    .fill(SoundChexTheme.base600)
                    .frame(height: 1)
            }
            // Past the safe area, so the fill reaches the bottom of the screen
            // rather than stopping above the home indicator.
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabContent(_ tab: MediaTab) -> some View {
        let isActive = selection == tab

        return VStack(spacing: 3) {
            // 1.75rem × 2px, on the top edge. Always laid out, so selecting a
            // tab does not shift the row by two points.
            Rectangle()
                .fill(isActive ? theme.accent : .clear)
                .frame(width: 28, height: 2)
                .clipShape(.rect(bottomLeadingRadius: 2, bottomTrailingRadius: 2))

            Spacer(minLength: 0)

            tab.icon
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 22, height: 22)

            Text(tab.title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.1)

            Spacer(minLength: 0)
        }
        // 3.25rem, the web's own minimum — and comfortably past the 44pt
        // Apple asks for a touch target.
        .frame(height: 52)
        .foregroundStyle(isActive ? SoundChexTheme.ink100 : SoundChexTheme.ink500)
        .contentShape(.rect)
    }
}

/// The four sections the media centre has.
enum MediaTab: String, CaseIterable, Identifiable {
    case home, watch, music, books

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .watch: "Watch"
        case .music: "Music"
        case .books: "Books"
        }
    }

    /// The web's own glyphs, not SF Symbols — the same shapes the media centre
    /// draws, so the two read as one product.
    ///
    /// `AnyShape` because these are four distinct `Shape` types and a stored
    /// property cannot be four things; the erasure costs nothing at four tabs.
    var icon: AnyShape {
        switch self {
        case .home: AnyShape(SoundChexIcons.Home())
        case .watch: AnyShape(SoundChexIcons.Watch())
        case .music: AnyShape(SoundChexIcons.Music())
        case .books: AnyShape(SoundChexIcons.Book())
        }
    }
}
