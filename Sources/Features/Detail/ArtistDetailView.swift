// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// An artist page, Spotify-style (spec §3): a rectangular hero banner with the
/// name overlaid, a dominant Play button, a "Popular" track list, then the
/// artist's albums.
///
/// Spotify's own artist page uses a banner (not a circle); circular artist art is
/// kept for rails and rows elsewhere. "Popular" is the artist's tracks in library
/// order — the app has no play-count signal to rank by, so it degrades to that
/// rather than inventing one (no server change; spec's out-of-scope rule).
struct ArtistDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadStore.self) private var downloads
    @Environment(ThemeStore.self) private var theme
    let artist: LibraryStore.Artist

    @State private var addingToPlaylist = false
    @State private var batchMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    /// Every track by the artist, album order then track order — the queue the
    /// Play button and the Popular list draw from.
    private var allTracks: [MediaItem] {
        artist.albums.flatMap(\.tracks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                banner
                secondaryActions
                popular
                albums
            }
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(artist.name)
        // Pushed screens do not inherit the tab root's inset, so the last
        // row would sit under the now-playing bar (S-343).
        .nowPlayingInset()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // Everything by the artist, in album then track order — the same set
        // the Play button uses (S-385).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CollectionActions(tracks: allTracks) { addingToPlaylist = true }
            }
        }
        .sheet(isPresented: $addingToPlaylist) {
            AddToPlaylistSheet(items: allTracks)
                .presentationDetents([.medium, .large])
                .soundchexTheme(theme)
        }
    }

    // MARK: - Banner

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage(url: artist.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(
                    Image(systemName: "music.mic").font(.largeTitle).foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipped()
            // A scrim so the name reads over any image, fading into the ground.
            .overlay(
                LinearGradient(
                    colors: [.clear, .clear, SoundChexTheme.base900.opacity(0.85), SoundChexTheme.base900],
                    startPoint: .top, endPoint: .bottom
                )
            )

            HStack(alignment: .bottom) {
                Text(artist.name)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                Spacer(minLength: 12)
                playFAB
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    /// Shuffle and download, under the banner — the same pair the album page
    /// offers, so downloading an artist does not mean opening every album
    /// (S-387).
    @ViewBuilder private var secondaryActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 20) {
                circleButton(system: "shuffle") {
                    if !playback.isShuffled { playback.toggleShuffle() }
                    playback.play(allTracks)
                }
                circleButton(system: "arrow.down") {
                    switch downloads.downloadAll(allTracks) {
                    case .started(let n): flash("Downloading \(n) songs…")
                    case .insufficientSpace: flash("Not enough free space.")
                    case .nothingToDo: flash("Already downloaded.")
                    }
                }
                Spacer()
            }

            // The result, said plainly. An artist's whole catalogue is a lot
            // to fetch, and "not enough free space" is the answer that most
            // needs saying.
            if let batchMessage {
                Text(batchMessage)
                    .font(.caption)
                    .foregroundStyle(SoundChexTheme.ink500)
            }
        }
        .padding(.horizontal, 16)
    }

    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(SoundChexTheme.ink200)
                .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
        }
    }

    private func flash(_ text: String) {
        batchMessage = text
        Task { try? await Task.sleep(for: .seconds(3)); batchMessage = nil }
    }

    private var playFAB: some View {
        Button {
            playback.play(allTracks)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(SoundChexTheme.accent, in: .circle)
                .shadow(color: SoundChexTheme.accent.opacity(0.4), radius: 12, y: 4)
        }
    }

    // MARK: - Popular

    @ViewBuilder private var popular: some View {
        let top = Array(allTracks.prefix(5))
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Popular")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .padding(.horizontal, 16)

                ForEach(Array(top.enumerated()), id: \.element.id) { pair in
                    let isCurrent = playback.current?.id == pair.element.id
                    Button {
                        playback.play(allTracks, startAt: pair.offset)
                    } label: {
                        HStack(spacing: 12) {
                            Group {
                                if isCurrent {
                                    PlayingEqualizer(isAnimating: playback.isPlaying, size: 20)
                                } else {
                                    Text("\(pair.offset + 1)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(SoundChexTheme.ink500)
                                }
                            }
                            .frame(width: 24)
                            Artwork(item: pair.element, size: 44)
                            Text(pair.element.title)
                                .foregroundStyle(isCurrent ? SoundChexTheme.accent : SoundChexTheme.ink100)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Albums

    private var albums: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SoundChexTheme.ink100)
                .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(artist.albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CachedImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700.overlay(
                                    Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500))
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
                            Text(album.title).font(.subheadline)
                                .foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                            Text("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")").font(.caption)
                                .foregroundStyle(SoundChexTheme.ink500)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
