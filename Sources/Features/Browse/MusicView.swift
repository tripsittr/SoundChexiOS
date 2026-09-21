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

    /// The active filter chip. `nil` is "everything" — the Recents landing
    /// (spec §1); a chip narrows to that one kind.
    @State private var section: Section?

    enum Section: String, CaseIterable {
        case playlists = "Playlists", albums = "Albums", artists = "Artists", songs = "Songs"
    }

    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader()
                FilterChipRow(options: Section.allCases, selection: $section) { $0.rawValue }
                content
                    // Pull down to sync the library — the quick way to reflect a
                    // server change (a merged duplicate, new music) on demand.
                    .refreshable { await store.load() }
            }
            .background(SoundChexTheme.base900)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private var content: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SoundChexTheme.base900)
        } else {
            switch section {
            case .none:
                recents

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

    /// The "everything" landing (no chip active) — the Recents surface from the
    /// references. It summarises the library (albums, then artists); the chips
    /// above do the exhaustive browse, and Playlists is a chip of its own since
    /// those live in a separate store. Kept to what LibraryStore actually holds.
    private var recents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !store.albums.isEmpty {
                    shelfHeader("Albums")
                    LazyVGrid(columns: grid, spacing: 20) {
                        ForEach(store.albums.prefix(6)) { album in
                            NavigationLink { AlbumDetailView(album: album) } label: { albumCell(album) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !store.artists.isEmpty {
                    shelfHeader("Artists")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(store.artists.prefix(10)) { artist in
                                NavigationLink { ArtistDetailView(artist: artist) } label: { artistCircle(artist) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
    }

    /// A circular artist tile for the recents shelf — artist art is a circle
    /// everywhere but the artist's own banner (spec).
    private func artistCircle(_ artist: LibraryStore.Artist) -> some View {
        VStack(spacing: 8) {
            CachedImage(url: artist.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(
                    Image(systemName: "music.mic").foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 112, height: 112)
            .clipShape(.circle)
            Text(artist.name)
                .font(.caption)
                .foregroundStyle(SoundChexTheme.ink200)
                .lineLimit(1)
                .frame(width: 112)
        }
    }

    private func shelfHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(SoundChexTheme.ink100)
            .padding(.horizontal, 16)
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
