import SwiftUI

/// The home screen: a cinematic hero over stacked horizontal rails, the way the
/// web home is laid out. The first rail pulls up over the hero's bottom fade.
struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let hero = store.heroItem {
                    HeroBanner(item: hero) { play(hero) }
                }

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.homeRows) { row in
                        Rail(title: row.title, items: row.items) { play($0) }
                    }
                }
                // Overlap the first rail onto the hero's fade.
                .padding(.top, store.heroItem == nil ? 16 : -24)
                .padding(.bottom, 24)
            }
        }
        .background(SoundChexTheme.base900)
        .ignoresSafeArea(edges: .top)
        // The account/settings entry — a circular button floating top-right over
        // the hero, the way the web header carries the account menu.
        .overlay(alignment: .topTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(SoundChexTheme.ink100)
                    .padding(10)
                    .background(.black.opacity(0.35), in: .circle)
                    .shadow(radius: 6)
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .overlay {
            if store.isLoading && store.items.isEmpty {
                ProgressView().tint(SoundChexTheme.accent)
            } else if let error = store.loadError, store.items.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "wifi.slash",
                                       description: Text(error))
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func play(_ item: MediaItem) {
        guard item.type == .music else { return }
        // Play the album/artist context when we can derive it; a single item
        // otherwise. Detail screens (IOS-04) will queue full track lists.
        playback.play([item])
    }
}

/// The hero: a blurred full-bleed backdrop with the title and a play/details
/// button, matching the web hero's treatment.
struct HeroBanner: View {
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
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(SoundChexTheme.accent)

                Text(item.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(SoundChexTheme.ink100)
                    .shadow(color: .black.opacity(0.85), radius: 12, y: 2)
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(SoundChexTheme.ink300)
                        .lineLimit(1)
                }

                if item.type == .music {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
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
        .frame(height: 440)
        .clipped()
    }

    private var backdrop: some View {
        GeometryReader { geo in
            AsyncImage(url: item.artwork) { image in
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
