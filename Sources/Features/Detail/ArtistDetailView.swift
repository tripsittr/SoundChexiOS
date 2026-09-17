// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// An artist: their albums in a grid. Tapping an album opens it.
struct ArtistDetailView: View {
    let artist: LibraryStore.Artist

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
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
                                Text("\(album.tracks.count) songs").font(.caption)
                                    .foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Circular artwork, eyebrow, name, and a meta line — the artist header shape
    /// from the spec (artist art is a circle, unlike the square album art).
    private var header: some View {
        VStack(spacing: 8) {
            CachedImage(url: artist.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(
                    Image(systemName: "music.mic").foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 128, height: 128)
            .clipShape(.circle)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            Text("Artist")
                .font(.caption2.bold()).tracking(1.5)
                .foregroundStyle(SoundChexTheme.ink500)
            Text(artist.name).font(.title3.bold())
                .foregroundStyle(SoundChexTheme.ink100).multilineTextAlignment(.center)
            Text("\(artist.albums.count) album\(artist.albums.count == 1 ? "" : "s") · \(artist.trackCount) song\(artist.trackCount == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(SoundChexTheme.ink500)
        }
        .padding(.top, 12)
    }
}
