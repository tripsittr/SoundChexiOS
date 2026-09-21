// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Manage the addresses that reach this SoundChex server (S-162).
///
/// The same server can be at a fast LAN address at home and a tunnel/relay
/// hostname away from it. The app races the known addresses on launch and uses
/// the fastest reachable one, so you get the ~20ms local path at home and the
/// tunnel elsewhere without switching anything. Here you add the alternates and
/// see which one is in use now.
struct ServerAddressesView: View {
    @Environment(Session.self) private var session

    @State private var newAddress = ""
    @State private var adding = false
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                addressRow(session.primaryURL, role: "Primary")
                ForEach(session.alternateURLs, id: \.self) { url in
                    addressRow(url, role: "Alternate")
                        .swipeActions {
                            Button(role: .destructive) {
                                session.removeAlternateURL(url)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                }
            } header: {
                Text("Addresses")
            } footer: {
                Text("The app uses whichever address answers fastest — a local address at home, the tunnel when you're away. The one in use now is marked.")
            }

            Section("Add an address") {
                TextField("192.168.1.10:8000 or my-server.ts.net", text: $newAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if let error {
                    Text(error).font(.caption).foregroundStyle(SoundChexTheme.errorPink)
                }

                Button {
                    add()
                } label: {
                    if adding { ProgressView() } else { Text("Add address") }
                }
                .disabled(newAddress.trimmingCharacters(in: .whitespaces).isEmpty || adding)
            }

            Section {
                Button {
                    Task {
                        checking = true
                        await session.reselectFastestAddress()
                        checking = false
                    }
                } label: {
                    HStack {
                        Label("Re-check connection", systemImage: "arrow.triangle.2.circlepath")
                        if checking { Spacer(); ProgressView() }
                    }
                }
            } footer: {
                Text("Runs the speed check again and switches to the fastest reachable address — handy right after moving between home and away.")
            }
        }
        .navigationTitle("Server addresses")
        .navigationBarTitleDisplayMode(.inline)
        .background(SoundChexTheme.base900)
    }

    private func addressRow(_ url: URL?, role: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(url?.host() ?? "—")
                    .foregroundStyle(SoundChexTheme.ink100)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(SoundChexTheme.ink500)
            }
            Spacer()
            if url == session.serverURL {
                Label("In use", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(SoundChexTheme.accent)
            }
        }
    }

    private func add() {
        error = nil
        guard let url = ServerURL.normalized(newAddress) else {
            error = "That does not look like a valid address."
            return
        }
        guard url != session.primaryURL, !session.alternateURLs.contains(url) else {
            error = "That address is already listed."
            return
        }

        adding = true
        Task {
            session.addAlternateURL(url)
            // Re-race so a just-added faster path is adopted immediately.
            await session.reselectFastestAddress()
            newAddress = ""
            adding = false
        }
    }
}
