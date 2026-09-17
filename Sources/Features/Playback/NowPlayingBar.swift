import SwiftUI

/// The persistent now-playing bar, docked above the tab bar while something
/// plays. Tapping it could later open a full-screen player; for now it shows
/// what's playing and the core transport.
struct NowPlayingBar: View {
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        if let item = playback.current {
            VStack(spacing: 0) {
                progressTrack

                HStack(spacing: 12) {
                    Artwork(item: item, size: 40)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SoundChexTheme.ink100)
                            .lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(SoundChexTheme.ink500)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button { playback.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    Button { playback.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .foregroundStyle(SoundChexTheme.ink100)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(SoundChexTheme.base700).frame(height: 0.5)
            }
        }
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            let fraction = playback.duration > 0 ? playback.position / playback.duration : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(SoundChexTheme.base700)
                Rectangle().fill(SoundChexTheme.accent)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 2)
    }
}
