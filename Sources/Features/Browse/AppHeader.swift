// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The persistent top bar shown on every page: a tappable search field on the
/// left and the account (profile) button on the right — the two things the user
/// wanted reachable everywhere, so neither is buried behind a tab.
///
/// Tapping search opens a full-screen search overlay; tapping the avatar opens
/// Settings (server, profile switch, downloads, admin). The bar paints its own
/// base-900 ground so it reads over any page, and sits inside each tab's safe
/// area rather than floating over content.
struct AppHeader: View {
    @Environment(Session.self) private var session
    @Environment(ThemeStore.self) private var theme

    @State private var searching = false
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 12) {
            Button { searching = true } label: {
                HStack(spacing: 8) {
                    // The web nav's own magnifier, not SF Symbols.
                    SoundChexIcons.Search()
                        .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                    Text("Search")
                        .font(.system(size: 15))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(SoundChexTheme.ink500)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(SoundChexTheme.base700, in: .capsule)
            }
            .buttonStyle(.plain)

            // A brand-accent chip rather than the system person.crop.circle —
            // the web account button is a coloured chip, so this echoes it and
            // stops the header reading as Apple Music's.
            Button { showingSettings = true } label: {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SoundChexTheme.base900)
        // Covers get a fresh environment, so carry the theme in explicitly —
        // otherwise Settings and Search fall back to the system light appearance
        // and blue tint.
        .fullScreenCover(isPresented: $searching) {
            SearchOverlay().soundchexTheme(theme)
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView().soundchexTheme(theme)
        }
    }
}

/// The search screen, presented from the header. A thin wrapper so the same
/// search UI works as a presented overlay with its own dismiss.
struct SearchOverlay: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SearchResultsList()
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
