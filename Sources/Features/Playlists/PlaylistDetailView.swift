// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI
import PhotosUI

/// One playlist, Spotify/Apple style: a big cover, the name and description, a
/// Play/Shuffle header, then the tracks — drag-reorderable, swipe-to-remove, and
/// editable behind a ⋯ menu. Changes persist to the server as they happen.
struct PlaylistDetailView: View {
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss

    let playlist: Playlist
    /// Called after an edit/delete so the list behind can refresh.
    var onChange: () -> Void = {}

    @State private var detail: PlaylistDetail?
    @State private var tracks: [MediaItem] = []
    @State private var loading = true
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowBackground(SoundChexTheme.base900)
                .listRowSeparator(.hidden)

            ForEach(tracks) { track in
                SongRow(item: track, queue: tracks, index: tracks.firstIndex(of: track) ?? 0)
                    .listRowBackground(SoundChexTheme.base900)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { remove(track) } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active)) // drag handles always on, like Spotify's edit
        .background(SoundChexTheme.base900)
        .navigationTitle(currentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit details", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay { if loading { ProgressView().tint(SoundChexTheme.accent) } }
        .task { await load() }
        .sheet(isPresented: $editing) {
            EditPlaylistSheet(playlist: displayPlaylist) { Task { await load(); onChange() } }
                .presentationDetents([.medium])
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("The songs stay in your library.")
        }
    }

    /// The playlist as currently known (detail once loaded, else the passed-in
    /// summary) — so edits show immediately.
    private var displayPlaylist: Playlist { playlist }
    private var currentName: String { detail?.name ?? playlist.name }

    private var header: some View {
        VStack(spacing: 14) {
            PlaylistCover(artworkURL: detail?.artworkURL ?? playlist.artworkURL,
                          mosaic: tracks.compactMap(\.artwork))
                .frame(width: 220, height: 220)
                .clipShape(.rect(cornerRadius: SoundChexTheme.radiusLargeArt))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            VStack(spacing: 6) {
                Text(currentName).font(.title3.bold()).foregroundStyle(SoundChexTheme.ink100)
                    .multilineTextAlignment(.center)
                if let desc = detail?.description, !desc.isEmpty {
                    Text(desc).font(.subheadline).foregroundStyle(SoundChexTheme.ink400)
                        .multilineTextAlignment(.center)
                }
                Text(metaLine).font(.caption).foregroundStyle(SoundChexTheme.ink500)
            }

            HStack(spacing: 12) {
                Button {
                    playback.play(tracks)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
                }
                Button {
                    if !playback.isShuffled { playback.toggleShuffle() }
                    playback.play(tracks)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(SoundChexTheme.ink200)
                        .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12).padding(.bottom, 8)
    }

    private var metaLine: String {
        var parts = ["\(tracks.count) song\(tracks.count == 1 ? "" : "s")"]
        if let ms = detail?.durationMs, ms > 0 { parts.append(durationText(ms)) }
        return parts.joined(separator: " · ")
    }

    private func durationText(_ ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) hr \(m) min" }
        return "\(m) min"
    }

    // MARK: - Data

    private func load() async {
        let d = try? await session.api?.playlist(playlist.id)
        detail = d
        tracks = d?.items ?? []
        loading = false
    }

    private func move(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        let order = tracks.map(\.id)
        Task { try? await session.api?.reorderPlaylist(playlist.id, order: order) }
    }

    private func remove(_ track: MediaItem) {
        tracks.removeAll { $0.id == track.id }
        Task {
            try? await session.api?.removeFromPlaylist(playlist.id, itemID: track.id)
            onChange()
        }
    }

    private func delete() {
        Task {
            try? await session.api?.deletePlaylist(playlist.id)
            onChange()
            dismiss()
        }
    }
}
