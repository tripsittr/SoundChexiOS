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
                        PlaylistsGrid()
                            .navigationTitle("Playlists")
                            .navigationBarTitleDisplayMode(.inline)
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
                    Button {
                        Task { await session.changeServer(); dismiss() }
                    } label: {
                        Label("Change server", systemImage: "server.rack")
                    }
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
                    Text(AppRelease.name.map { "SoundChex for iOS · “\($0)”" } ?? "SoundChex for iOS")
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

    private var appVersion: String { AppRelease.displayWithBuild }
}
