// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Account and app settings: the current profile, switching profile, signing
/// out, and (later) downloads and playback preferences.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeStore.self) private var theme

    @State private var switching = false
    @State private var diagnosticsSent = false

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
                    NavigationLink {
                        ServerAddressesView()
                    } label: {
                        LabeledContent("Address", value: session.serverURL?.host() ?? "—")
                    }
                    Button {
                        Task { await session.changeServer(); dismiss() }
                    } label: {
                        Label("Change server", systemImage: "server.rack")
                    }
                }

                Section("Personalise") {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                }

                Section {
                    Button {
                        downloads.refreshStorageSnapshot()

                        let formatter = ByteCountFormatter()
                        formatter.countStyle = .file
                        let used = formatter.string(fromByteCount: downloads.storedBytesUsed)
                        let free = downloads.freeBytesAvailable == .max
                            ? "unknown"
                            : formatter.string(fromByteCount: downloads.freeBytesAvailable)
                        let host = session.serverURL?.host() ?? "unknown"
                        let reason = "manual from settings: host=\(host), downloaded_items=\(downloads.storedItemCount), downloaded_bytes=\(downloads.storedBytesUsed), downloaded_used=\(used), free_bytes=\(downloads.freeBytesAvailable), free=\(free)"

                        AppLog.info("Manual diagnostics requested from settings", category: "diagnostics")
                        DeviceReporter.shared.sendDiagnostics(reason: reason)
                        diagnosticsSent = true
                    } label: {
                        Label(diagnosticsSent ? "Diagnostics sent" : "Send diagnostics",
                              systemImage: diagnosticsSent ? "checkmark.circle" : "stethoscope")
                    }
                    .disabled(diagnosticsSent)
                } footer: {
                    Text("Sends recent app logs to your server's Device Reports, and crash reports are sent automatically on the next launch. No media or account details are included.")
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

                // Transparency: the same project links the served web app puts
                // in its footer, so the source, licence and policies are
                // reachable from inside the iOS app too. SoundChex is AGPLv3 and
                // stores none of the user's media off their own machine; saying
                // so here, with every link to prove it, is the point.
                Section {
                    Link(destination: ProjectLinks.source) {
                        Label("Source (AGPLv3)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: ProjectLinks.licence) {
                        Label("Licence", systemImage: "doc.text")
                    }
                    Link(destination: ProjectLinks.privacy) {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    Link(destination: ProjectLinks.terms) {
                        Label("Terms", systemImage: "text.book.closed")
                    }
                    Link(destination: ProjectLinks.credits) {
                        Label("Open-source credits", systemImage: "heart")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Free and open source. Your media stays on your own server — SoundChex neither acquires your files nor helps you to.")
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
                ProfileSwitcherView { dismiss() }.soundchexTheme(theme)
            }
        }
    }

    private var appVersion: String { AppRelease.display }
}
