// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Applies the user's theme (appearance + accent) to a view.
///
/// SwiftUI does not carry `.preferredColorScheme` or `.tint` from the root into
/// a `sheet` or `fullScreenCover` — a presentation gets a fresh environment. So
/// anything presented that way (Settings, the full player, search) would fall
/// back to the system light appearance and the system blue tint. Attaching
/// `.soundchexTheme()` inside each presentation fixes that, and re-injects the
/// ThemeStore so nested views can read it.
struct SoundChexThemeModifier: ViewModifier {
    /// Captured from the presenting view, because the presented content's own
    /// environment does not yet have the store.
    let theme: ThemeStore

    func body(content: Content) -> some View {
        content
            .environment(theme)
            .tint(theme.accent)
            .preferredColorScheme(theme.appearance.colorScheme)
    }
}

extension View {
    /// Carry the SoundChex theme into a presented sheet or cover. Pass the store
    /// captured from the presenting view (the presentation has none of its own).
    func soundchexTheme(_ theme: ThemeStore) -> some View {
        modifier(SoundChexThemeModifier(theme: theme))
    }
}
