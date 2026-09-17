import SwiftUI

/// A show or film: artwork header, and episodes grouped by season (for a show).
/// A film with no children just shows its own play/detail.
struct ShowDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    let item: MediaItem

    /// The item to play in the video player, when one is tapped.
    @State private var playing: MediaItem?

    private var episodes: [MediaItem] { store.children(of: item.id) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if episodes.isEmpty {
                    // A film, or a show with no episodes catalogued.
                    if item.playable {
                        playButton(for: item, label: "Play")
                            .padding(.horizontal, 16)
                    }
                } else {
                    episodeList
                }
            }
            .padding(.bottom, 24)
        }
        .background(SoundChexTheme.base900)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { toPlay in
            VideoPlayerView(item: toPlay)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Artwork(item: item, size: 220, aspect: 1.5)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            Text(eyebrow)
                .font(.caption2.bold()).tracking(1.5)
                .foregroundStyle(SoundChexTheme.ink500)
            Text(item.title).font(.title3.bold()).foregroundStyle(SoundChexTheme.ink100)
                .multilineTextAlignment(.center)
            if let meta = metaLine {
                Text(meta).font(.subheadline).foregroundStyle(SoundChexTheme.ink500)
            }
        }
        .padding(.top, 12)
    }

    private var eyebrow: String {
        episodes.isEmpty ? "Film" : "Show"
    }

    /// "2024 · 3 seasons" for a show, "2024" for a film, or the subtitle — the
    /// "·"-joined meta line, skipping missing parts.
    private var metaLine: String? {
        var parts: [String] = []
        if let year = item.meta?.releaseYear { parts.append(String(year)) }
        if !episodes.isEmpty {
            let seasons = Set(episodes.compactMap { $0.meta?.seasonNumber }).count
            if seasons > 0 { parts.append("\(seasons) season\(seasons == 1 ? "" : "s")") }
        } else if let subtitle = item.subtitle {
            parts.append(subtitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groupedBySeason, id: \.season) { group in
                if group.season > 0 {
                    Text("Season \(group.season)")
                        .font(.system(size: 13, weight: .semibold)).tracking(1).textCase(.uppercase)
                        .foregroundStyle(SoundChexTheme.ink500)
                        .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 6)
                }
                ForEach(group.episodes) { episode in
                    Button {
                        playing = episode
                    } label: {
                        HStack(spacing: 12) {
                            if let n = episode.meta?.episodeNumber {
                                Text("\(n)").font(.subheadline.monospacedDigit())
                                    .foregroundStyle(SoundChexTheme.ink500).frame(width: 28)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.meta?.episodeTitle ?? episode.title)
                                    .foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(SoundChexTheme.ink400)
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

    private func playButton(for item: MediaItem, label: String) -> some View {
        Button {
            playing = item
        } label: {
            Label(label, systemImage: "play.fill")
                .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
        }
    }

    /// Episodes grouped by season number, in order.
    private var groupedBySeason: [(season: Int, episodes: [MediaItem])] {
        let groups = Dictionary(grouping: episodes) { $0.meta?.seasonNumber ?? 0 }
        return groups.keys.sorted().map { season in
            (season, groups[season]!.sorted { ($0.meta?.episodeNumber ?? 0) < ($1.meta?.episodeNumber ?? 0) })
        }
    }
}
