// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The Music tab: Songs / Albums / Artists, chosen with a pill sub-nav — the
/// native equivalent of the web music sub-nav (999px pills, accent when active).
///
/// The pills sit in a fixed bar under the nav title rather than a `safeAreaInset`
/// (which left an invisible empty header on the list) or the toolbar's principal
/// slot (a segmented control, not the spec's pills).
struct MusicView: View {
    @Environment(LibraryStore.self) private var store
    @State private var section: Section = .songs

    enum Section: String, CaseIterable {
        case songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists"
    }

    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader()
                subNav
                content
            }
            .background(SoundChexTheme.base900)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The pill row. Horizontally scrollable so four pills never crowd a narrow
    /// phone. Its own bar so it never collapses to an empty header.
    private var subNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases, id: \.self) { item in
                    let active = item == section
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { section = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(active ? .white : SoundChexTheme.ink400)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(active ? SoundChexTheme.accent : SoundChexTheme.base700, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(SoundChexTheme.base900)
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SoundChexTheme.base900)
        } else {
            switch section {
            case .songs:
                let songs = store.items(of: .music)
                List(Array(songs.enumerated()), id: \.element.id) { pair in
                    SongRow(item: pair.element, queue: songs, index: pair.offset)
                        .listRowBackground(SoundChexTheme.base900)
                }
                .listStyle(.plain)

            case .albums:
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 20) {
                        ForEach(store.albums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album)
                            } label: { albumCell(album) }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .background(SoundChexTheme.base900)

            case .playlists:
                PlaylistsGrid()

            case .artists:
                List(store.artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        HStack(spacing: 12) {
                            CachedImage(url: artist.artwork) { $0.resizable().scaledToFill() } placeholder: {
                                SoundChexTheme.base700.overlay(
                                    Image(systemName: "music.mic").foregroundStyle(SoundChexTheme.ink500))
                            }
                            .frame(width: 44, height: 44).clipShape(.circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                                Text("\(artist.albums.count) album\(artist.albums.count == 1 ? "" : "s")").font(.caption)
                                    .foregroundStyle(SoundChexTheme.ink500)
                            }
                        }
                    }
                    .listRowBackground(SoundChexTheme.base900)
                }
                .listStyle(.plain)
            }
        }
    }

    private func albumCell(_ album: LibraryStore.Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(
                    Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500))
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusPoster))
            Text(album.title).font(.subheadline).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
            Text(album.artist).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
        }
    }
}
