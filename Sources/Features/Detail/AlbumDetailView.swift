import SwiftUI

/// An album: big artwork, a Play/Shuffle header, then its tracks. Tapping a
/// track plays the album from there.
struct AlbumDetailView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadStore.self) private var downloads
    let album: LibraryStore.Album

    @State private var batchMessage: String?

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
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 12) {
            AsyncImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 200, height: 200)
            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusLargeArt))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            VStack(spacing: 4) {
                Text(album.title).font(.title3.bold()).foregroundStyle(SoundChexTheme.ink100)
                    .multilineTextAlignment(.center)
                Text(album.artist).font(.subheadline).foregroundStyle(SoundChexTheme.ink400)
                Text("\(album.tracks.count) songs").font(.caption).foregroundStyle(SoundChexTheme.ink500)
            }

            HStack(spacing: 12) {
                Button {
                    playback.play(album.tracks)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
                }
                Button {
                    if !playback.isShuffled { playback.toggleShuffle() }
                    playback.play(album.tracks)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(SoundChexTheme.base700, in: .capsule).foregroundStyle(SoundChexTheme.ink100)
                }

                // Download the whole album.
                Button {
                    switch downloads.downloadAll(album.tracks) {
                    case .started(let n): flash("Downloading \(n) songs…")
                    case .insufficientSpace: flash("Not enough free space.")
                    case .nothingToDo: flash("Already downloaded.")
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(SoundChexTheme.base700, in: .circle)
                        .foregroundStyle(SoundChexTheme.ink200)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4)

            if let batchMessage {
                Text(batchMessage).font(.caption).foregroundStyle(SoundChexTheme.ink500)
            }
        }
        .padding(.top, 12)
    }

    private func flash(_ text: String) {
        batchMessage = text
        Task { try? await Task.sleep(for: .seconds(3)); batchMessage = nil }
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { pair in
                Button {
                    playback.play(album.tracks, startAt: pair.offset)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(pair.element.meta?.trackNumber ?? pair.offset + 1)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(SoundChexTheme.ink500)
                            .frame(width: 28)
                        Text(pair.element.title).foregroundStyle(SoundChexTheme.ink100).lineLimit(1)
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
