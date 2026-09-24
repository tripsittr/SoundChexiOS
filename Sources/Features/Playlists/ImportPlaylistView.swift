// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI
import UniformTypeIdentifiers

/// Port a playlist into the library from a file (S-313).
///
/// Pick an M3U / CSV / XSPF playlist file; it is uploaded, matched to the library
/// on the server, and saved as a playlist. What matched is confirmed, and the
/// tracks that didn't are listed so they can be resolved to a library song or
/// left out. The mobile face of the porting engine the desktop plugin also uses.
struct ImportPlaylistView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onFinished: () -> Void

    @State private var picking = false
    @State private var phase: Phase = .idle
    @State private var result: APIClient.PlaylistImport?
    @State private var error: String?

    enum Phase { case idle, importing, done }

    private let playlistTypes: [UTType] = [
        .init(filenameExtension: "m3u") ?? .plainText,
        .init(filenameExtension: "m3u8") ?? .plainText,
        .commaSeparatedText,
        .init(filenameExtension: "xspf") ?? .xml,
        .plainText, .xml,
    ]

    var body: some View {
        NavigationStack {
            content
                .background(SoundChexTheme.base900)
                .navigationTitle("Import Playlist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { onFinished(); dismiss() }
                    }
                }
                .fileImporter(isPresented: $picking, allowedContentTypes: playlistTypes) { outcome in
                    handlePick(outcome)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            picker
        case .importing:
            VStack(spacing: 12) {
                ProgressView().tint(SoundChexTheme.accent)
                Text("Matching to your library…")
                    .font(.footnote).foregroundStyle(SoundChexTheme.ink400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done:
            if let result { ImportResultView(result: result) }
        }
    }

    private var picker: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(SoundChexTheme.ink500)
            Text("Bring a playlist with you")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SoundChexTheme.ink100)
            Text("Choose an M3U, CSV, or XSPF file. Its songs are matched to your library and saved as a playlist.")
                .font(.subheadline)
                .foregroundStyle(SoundChexTheme.ink400)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button { picking = true } label: {
                Text("Choose a file")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(SoundChexTheme.accent, in: Capsule())
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handlePick(_ outcome: Result<URL, Error>) {
        error = nil

        guard case .success(let url) = outcome else {
            if case .failure(let e) = outcome { error = e.localizedDescription }
            return
        }

        // A picked file is security-scoped; read it, then import.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."
            return
        }

        let filename = url.lastPathComponent
        phase = .importing

        Task {
            do {
                let imported = try await session.api?.importPlaylistFile(data, filename: filename, name: nil)
                result = imported
                phase = .done
                onFinished()
            } catch {
                self.error = (error as? APIClient.APIError)?.errorDescription ?? "That file couldn't be imported."
                phase = .idle
            }
        }
    }
}

/// The outcome of an import: what matched, and the tracks to resolve.
private struct ImportResultView: View {
    @Environment(Session.self) private var session
    @State var result: APIClient.PlaylistImport

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name ?? "Imported playlist")
                        .font(.headline).foregroundStyle(SoundChexTheme.ink100)
                    Text("\(result.matched) of \(result.total) songs matched your library")
                        .font(.subheadline).foregroundStyle(SoundChexTheme.ink400)
                }
                .listRowBackground(SoundChexTheme.base800)
            }

            if !result.unmatched.isEmpty {
                Section("Not in your library (\(result.unmatched.count))") {
                    ForEach(Array(result.unmatched.enumerated()), id: \.element.id) { index, track in
                        UnmatchedRow(track: track) { itemID in
                            await resolve(index: index, itemID: itemID)
                        }
                        .listRowBackground(SoundChexTheme.base800)
                    }
                }
            } else {
                Section {
                    Label("Every song was matched.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .listRowBackground(SoundChexTheme.base800)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoundChexTheme.base900)
    }

    private func resolve(index: Int, itemID: Int) async {
        if let updated = try? await session.api?.resolvePlaylistImport(result.id, index: index, itemID: itemID) {
            result = updated
        }
    }
}

/// One unmatched track, with a search field to pick the library song it is.
private struct UnmatchedRow: View {
    let track: APIClient.PlaylistImport.Unmatched
    let onResolve: (Int) async -> Void

    @Environment(Session.self) private var session
    @State private var query = ""
    @State private var matches: [MediaItem] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(track.title ?? track.sourceLabel ?? "Unknown track")
                .font(.subheadline).foregroundStyle(SoundChexTheme.ink100)
            if let artist = track.artist {
                Text(artist).font(.caption).foregroundStyle(SoundChexTheme.ink500)
            }

            TextField("Search your library to match…", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: query) { _, q in Task { await search(q) } }

            ForEach(matches.prefix(4)) { item in
                Button {
                    Task { await onResolve(item.id) }
                } label: {
                    HStack {
                        Text(item.title).font(.caption).foregroundStyle(SoundChexTheme.ink200)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(SoundChexTheme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func search(_ q: String) async {
        let term = q.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { matches = []; return }
        matches = (try? await session.api?.search(term))?.filter { $0.type == .music } ?? []
    }
}
