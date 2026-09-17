import SwiftUI

/// Account and app settings: the current profile, switching profile, signing
/// out, and (later) downloads and playback preferences.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var switching = false

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    NavigationLink {
                        PlaylistsView()
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }

                // Admin, only for a profile that may administer.
                if session.isAdmin {
                    Section("Admin") {
                        NavigationLink {
                            AdminDashboardView()
                        } label: {
                            Label("Dashboard", systemImage: "chart.bar.xaxis")
                        }
                        NavigationLink {
                            AdminProfilesView()
                        } label: {
                            Label("Profiles", systemImage: "person.2.badge.gearshape")
                        }
                        Button {
                            Task { try? await session.api?.triggerScan() }
                        } label: {
                            Label("Scan for new media", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Server") {
                    LabeledContent("Address", value: session.serverURL?.host() ?? "—")
                }

                Section("Profile") {
                    Button {
                        switching = true
                    } label: {
                        Label("Switch profile", systemImage: "person.2.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            await session.signOut()
                            dismiss()
                        }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("SoundChex for iOS")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SoundChexTheme.base900)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $switching) {
                ProfileSwitcherView { dismiss() }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        // The music-themed name for this minor release — see Plans/Versioning.md.
        if let name = AppRelease.name(for: v) {
            return "\(v) “\(name)” (\(b))"
        }
        return "\(v) (\(b))"
    }
}

/// Maps a SemVer to its release name. Kept here so the version line and any
/// about screen read from one place.
enum AppRelease {
    private static let names: [String: String] = [
        "0.2": "Overture",
        "0.3": "Crescendo",
        "1.0": "Encore",
    ]

    /// The name for a full version string like "0.2.1" — keyed on its minor.
    static func name(for version: String) -> String? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return names["\(parts[0]).\(parts[1])"]
    }
}
