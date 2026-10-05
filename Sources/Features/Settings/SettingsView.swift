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
    @Environment(LibraryStore.self) private var store

    /// True while a scan and the refresh after it are running.
    @State private var scanning = false

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
                            Task { await scanAndRefresh() }
                        } label: {
                            // The state is on the row because a scan is not
                            // instant and the button otherwise looked inert —
                            // tapping it twice was the obvious response.
                            Label(
                                scanning ? "Scanning…" : "Scan for new media",
                                systemImage: scanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                            )
                        }
                        .disabled(scanning)
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

    /// Scan, wait for it, then pull the catalogue down again (S-450).
    ///
    /// The button used to fire the scan and stop there, so nothing on the
    /// phone changed until the next launch — the scan worked and looked as
    /// though it had not.
    ///
    /// The wait is the awkward part: `/admin/scan` queues the work and returns
    /// immediately, so there is nothing to await. Rather than poll for a
    /// completion the API does not report, this gives the server a moment and
    /// then reloads. A scan of a large library outlasts that, which is why the
    /// reload is a full fetch rather than a delta — a second tap, or the next
    /// pull-to-refresh, picks up whatever finished later.
    private func scanAndRefresh() async {
        guard !scanning, let api = session.api else { return }

        scanning = true
        defer { scanning = false }

        do {
            try await api.triggerScan()
        } catch {
            AppLog.error("Scan request failed: \(error.localizedDescription)", category: "library")
            // Still refresh: the scan may have been queued before the response
            // was lost, and a stale catalogue helps nobody either way.
        }

        // Long enough for a small library to finish and for the queue to have
        // started on a large one.
        try? await Task.sleep(for: .seconds(3))

        await store.reloadEverything()
    }

    private var appVersion: String { AppRelease.display }
}
