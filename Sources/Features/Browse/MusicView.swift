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
    @Environment(RecentContextsStore.self) private var recents
    @Environment(PlaylistStore.self) private var playlists

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
                yourLibrary

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

    /// The "everything" landing (no chip active): Your Library — what you last
    /// played, newest first (S-392).
    ///
    /// It used to list Albums then Artists, which is exactly what the chips
    /// above already do, so the landing was a worse copy of the next tap. What
    /// it shows now is history, and history the app records by *context*: put
    /// on an artist and the artist is here, tap a track inside an album and
    /// the album is here. See `RecentContextsStore`.
    ///
    /// Until there is history — a fresh install, or just after a sign-out —
    /// it falls back to the old browse shelves. An empty page on first launch
    /// would be worse than a redundant one.
    private var yourLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if recentRows.isEmpty {
                    browseShelves
                } else {
                    shelfHeader("Your Library")
                    ForEach(recentRows) { row in
                        recentRow(row)
                    }
                }

                // Suggestions under the history (S-413). Built from what the
                // device already knows, so they appear as soon as there is
                // anything to go on rather than waiting for a recommender.
                ForEach(shelves) { shelf in
                    shelfHeader(shelf.title)
                    albumRail(shelf.albums)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
    }

    /// One remembered thing, resolved from its stored id to the live object.
    /// Ids are resolved on read rather than cached because albums and artists
    /// are recomputed from the catalogue on every access — and because a
    /// context whose album has since left the library should simply vanish
    /// from the page rather than 404 on tap.
    private enum RecentRow: Identifiable {
        case artist(LibraryStore.Artist)
        case album(LibraryStore.Album)
        case playlist(Playlist)
        case song(MediaItem)

        var id: String {
            switch self {
            case .artist(let a): "artist:\(a.id)"
            case .album(let a): "album:\(a.id)"
            case .playlist(let p): "playlist:\(p.id)"
            case .song(let s): "song:\(s.id)"
            }
        }
    }

    /// Suggestion shelves, recomputed when the library or history changes.
    private var shelves: [LibraryShelves.Shelf] {
        LibraryShelves.build(store: store, recents: recents)
    }

    /// A horizontal row of album tiles — the shape the shelves use, and the
    /// same cell the browse grid draws so a suggestion looks like the library
    /// rather than a different feature bolted on.
    private func albumRail(_ albums: [LibraryStore.Album]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(albums) { album in
                    NavigationLink { AlbumDetailView(album: album) } label: {
                        albumCell(album)
                            .frame(width: 150)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var recentRows: [RecentRow] {
        // `store.albums`, `store.artists` and `items(of:)` are all computed —
        // each one regroups the whole catalogue on access. Looking them up
        // inside the loop would regroup thousands of tracks once per entry,
        // every time this view re-rendered; hoisting to a dictionary does it
        // once and turns each lookup into a hash.
        let albums = Dictionary(store.albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let artists = Dictionary(store.artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let playlistsByID = Dictionary(playlists.playlists.map { (String($0.id), $0) },
                                       uniquingKeysWith: { first, _ in first })
        let songs = Dictionary(store.items(of: .music).map { (String($0.id), $0) },
                               uniquingKeysWith: { first, _ in first })

        return recents.entries.compactMap { entry in
            switch entry.kind {
            case .artist: artists[entry.id].map(RecentRow.artist)
            case .album: albums[entry.id].map(RecentRow.album)
            case .playlist: playlistsByID[entry.id].map(RecentRow.playlist)
            case .song: songs[entry.id].map(RecentRow.song)
            }
        }
    }

    /// The old browse landing, kept for the no-history case.
    @ViewBuilder private var browseShelves: some View {
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

    /// One Your Library row: artwork, name, and what kind of thing it is.
    ///
    /// A flat list rather than a shelf per kind, because the ordering *is* the
    /// information — the most recent thing belongs at the top whether it is an
    /// artist or a song, and four near-empty shelves would bury it.
    @ViewBuilder private func recentRow(_ row: RecentRow) -> some View {
        switch row {
        case .artist(let artist):
            NavigationLink { ArtistDetailView(artist: artist) } label: {
                rowLabel(artwork: artist.artwork, title: artist.name,
                         subtitle: "Artist", circular: true,
                         placeholder: "music.mic")
            }
            .buttonStyle(.plain)

        case .album(let album):
            NavigationLink { AlbumDetailView(album: album) } label: {
                rowLabel(artwork: album.artwork, title: album.title,
                         subtitle: "Album · \(album.artist)", circular: false,
                         placeholder: "music.note")
            }
            .buttonStyle(.plain)

        case .playlist(let playlist):
            NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                rowLabel(artwork: playlist.artworkURL, title: playlist.name,
                         subtitle: "Playlist", circular: false,
                         placeholder: "music.note.list")
            }
            .buttonStyle(.plain)

        case .song(let item):
            SongRow(item: item)
                .padding(.horizontal, 16)
        }
    }

    private func rowLabel(artwork: URL?, title: String, subtitle: String,
                          circular: Bool, placeholder: String) -> some View {
        HStack(spacing: 12) {
            CachedImage(url: artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(
                    Image(systemName: placeholder).foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 56, height: 56)
            .clipShape(circular ? AnyShape(.circle)
                                : AnyShape(.rect(cornerRadius: SoundChexTheme.radiusPoster)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(SoundChexTheme.ink500).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
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
