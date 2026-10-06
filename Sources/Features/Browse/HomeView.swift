// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// The home screen: a cinematic hero over stacked horizontal rails, the way the
/// web home is laid out. The first rail pulls up over the hero's bottom fade.
struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var playback

    /// What the stack is showing. Driven by a path rather than by wrapping
    /// each tile in a `NavigationLink`, because `Rail` takes a tap closure and
    /// is shared with screens that do other things with it.
    @State private var path: [MediaItem] = []

    var body: some View {
        // Home was the only page without one, which is why nothing here could
        // navigate: `LibraryTabs` switches pages by hand and says "each page
        // keeps its own NavigationStack". A `NavigationLink` outside a stack
        // renders as a plain label and swallows the tap.
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: MediaItem.self) { item in
                    destination(for: item)
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // The persistent search + account bar, on Home as on every page.
            AppHeader()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let hero = store.dynamicHero {
                        // The button plays; the banner itself opens the page.
                        // Two different intentions, and conflating them is how
                        // a tap on a film did nothing at all.
                        NavigationLink {
                            destination(for: hero)
                        } label: {
                            HeroBanner(item: hero) { play(hero) }
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.homeRows) { row in
                            Rail(title: row.title, items: row.items) { open($0) }
                        }
                    }
                    // Overlap the first rail onto the hero's fade.
                    .padding(.top, store.dynamicHero == nil ? 16 : -24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(SoundChexTheme.base900)
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ProgressView().tint(SoundChexTheme.accent)
            } else if let error = store.loadError, store.items.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "wifi.slash",
                                       description: Text(error))
            }
        }
        // Fetched rather than derived: resume position is not in the mirror
        // (S-414). Refreshed on every appearance because "continue watching"
        // is exactly the row that goes stale — you watched something, came
        // back, and it should have moved.
        .task { await store.loadContinue() }
        .refreshable {
            await store.load()
            await store.loadContinue()
        }
    }

    /// What a tap on a tile does.
    ///
    /// Opening, not playing. `play()` below guarded on `.music` and returned
    /// for everything else, so tapping a film or a show on Home did **nothing
    /// at all** -- and tapping a song started it immediately with no way to
    /// see what it was. A tile is a thing to look at; the play button is what
    /// plays it.
    private func open(_ item: MediaItem) {
        path.append(item)
    }

    /// The screen behind a tile.
    ///
    /// `ShowDetailView` already handles films as well as shows -- its own
    /// docblock says "a show or film" -- so there is no separate movie screen
    /// to write. Music opens its album where it has one, since a track on its
    /// own is a thin page and the album is what somebody is looking for.
    @ViewBuilder
    private func destination(for item: MediaItem) -> some View {
        switch item.type {
        case .music:
            // The album the store already grouped this track into, found by
            // the id it builds -- rather than assembling an `Album` here,
            // which would differ from the one every other screen shows.
            if let album = store.albums.first(where: { $0.tracks.contains(item) }) {
                AlbumDetailView(album: album)
            } else {
                ShowDetailView(item: item)
            }
        default:
            ShowDetailView(item: item)
        }
    }

    private func play(_ item: MediaItem) {
        guard item.type == .music else { return }
        // Play the album/artist context when we can derive it; a single item
        // otherwise.
        playback.play([item])
    }
}

/// The hero: a blurred full-bleed backdrop with the title and a play/details
/// button, matching the web hero's treatment.
struct HeroBanner: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let item: MediaItem
    var onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop

            // Bottom + a touch of left scrim, so the title reads.
            LinearGradient(
                stops: [
                    .init(color: SoundChexTheme.base900, location: 0),
                    .init(color: SoundChexTheme.base900.opacity(0.55), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .bottom, endPoint: .top
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Recently added")
                    .font(ScaledFont.system(size: 12, relativeTo: .caption, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(theme.readableAccent(on: colorScheme))

                Text(item.title)
                    .font(ScaledFont.system(size: 34, relativeTo: .largeTitle, weight: .heavy))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .shadow(color: .black.opacity(0.85), radius: 12, y: 2)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(ScaledFont.system(size: 17, relativeTo: .body))
                        .foregroundStyle(SoundChexTheme.ink300)
                        .lineLimit(1)
                }

                if item.type == .music {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(ScaledFont.system(size: 14, relativeTo: .footnote, weight: .bold))
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(SoundChexTheme.ink100, in: .rect(cornerRadius: 6))
                            .foregroundStyle(SoundChexTheme.base900)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        // Taller where the screen is (S-408). 440pt is most of a phone and a
        // third of an iPad, which makes the hero read as a banner rather than
        // the front of the library.
        .frame(height: horizontalSizeClass == .regular ? 560 : 440)
        .clipped()
    }

    private var backdrop: some View {
        GeometryReader { geo in
            CachedImage(url: item.artwork) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                SoundChexTheme.base800
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1.1)
            .blur(radius: 30)
            .brightness(-0.2)
            .saturation(1.4)
            .clipped()
        }
    }
}
