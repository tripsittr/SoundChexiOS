// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// An album: big artwork, a Play/Shuffle header, then its tracks. Tapping a
/// track plays the album from there.
struct AlbumDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadStore.self) private var downloads
    @Environment(ThemeStore.self) private var theme
    let album: LibraryStore.Album

    @State private var batchMessage: String?
    @State private var addingToPlaylist = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                trackList
            }
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(album.title)
        // Pushed screens do not inherit the tab root's inset, so the last
        // row would sit under the now-playing bar (S-343).
        .nowPlayingInset()
        .navigationBarTitleDisplayMode(.inline)
        // Act on the whole record, rather than a track at a time from the row
        // kebabs (S-385).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CollectionActions(tracks: album.tracks) { addingToPlaylist = true }
            }
        }
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(items: album.tracks)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            // The cover sits large over a gradient from a muted tint of the
            // ground to base-900, Spotify-style (spec §3).
            CachedImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 220, height: 220)
            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusLargeArt))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .padding(.top, 8)

            // Title + meta, left-aligned, with the dominant round accent Play
            // FAB pulled to the trailing edge — the reference's play button.
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(SoundChexTheme.ink100)
                        .lineLimit(2)
                    Text(metaLine)
                        .font(.system(size: 13))
                        .foregroundStyle(SoundChexTheme.ink400)
                }
                Spacer(minLength: 12)
                playFAB
            }
            .padding(.horizontal, 16)

            // Secondary actions in a row under the title: shuffle and download.
            HStack(spacing: 20) {
                circleButton(system: "shuffle") {
                    if !playback.isShuffled { playback.toggleShuffle() }
                    playback.play(album.tracks)
                }
                circleButton(system: "arrow.down") {
                    switch downloads.downloadAll(album.tracks) {
                    case .started(let n): flash("Downloading \(n) songs…")
                    case .insufficientSpace: flash("Not enough free space.")
                    case .nothingToDo: flash("Already downloaded.")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if let batchMessage {
                Text(batchMessage).font(.caption).foregroundStyle(SoundChexTheme.ink500)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
        .background(
            LinearGradient(
                colors: [SoundChexTheme.base700.opacity(0.6), SoundChexTheme.base900],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    /// The dominant round accent Play button — Spotify's green circle, here red.
    private var playFAB: some View {
        Button {
            playback.play(album.tracks)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(SoundChexTheme.accent, in: .circle)
                .shadow(color: SoundChexTheme.accent.opacity(0.4), radius: 12, y: 4)
        }
    }

    /// A 44px bordered circle icon button — the secondary detail-screen action
    /// shape (shuffle, download) from the spec.
    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(SoundChexTheme.ink200)
                .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
        }
    }

    /// "Artist · 2019 · 12 songs" — the "·"-joined meta line from the spec,
    /// skipping any part that is missing.
    private var metaLine: String {
        var parts = [album.artist]
        if let year = album.tracks.first?.meta?.releaseYear { parts.append(String(year)) }
        parts.append("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private func flash(_ text: String) {
        batchMessage = text
        Task { try? await Task.sleep(for: .seconds(3)); batchMessage = nil }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { pair in
                let isCurrent = playback.current?.id == pair.element.id
                Button {
                    playback.play(album.tracks, startAt: pair.offset)
                } label: {
                    HStack(spacing: 12) {
                        // The playing track shows the equalizer in place of its
                        // number (spec §4).
                        Group {
                            if isCurrent {
                                PlayingEqualizer(isAnimating: playback.isPlaying, size: 20)
                            } else {
                                Text("\(pair.element.meta?.trackNumber ?? pair.offset + 1)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                        .frame(width: 28)
                        Text(pair.element.title)
                            .foregroundStyle(isCurrent ? SoundChexTheme.accent : SoundChexTheme.ink100)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Divider().overlay(SoundChexTheme.base700).padding(.leading, 56)
            }
        }
    }
}
