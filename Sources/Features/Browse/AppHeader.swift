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

    @State private var searching = false
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 12) {
            Button { searching = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Search")
                        .font(.system(size: 15))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(SoundChexTheme.ink500)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(SoundChexTheme.base700, in: .capsule)
            }
            .buttonStyle(.plain)

            Button { showingSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(SoundChexTheme.ink100)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SoundChexTheme.base900)
        .fullScreenCover(isPresented: $searching) {
            SearchOverlay()
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
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
