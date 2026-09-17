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
            CachedImage(url: album.artwork) { $0.resizable().scaledToFill() } placeholder: {
                SoundChexTheme.base700.overlay(Image(systemName: "music.note").foregroundStyle(SoundChexTheme.ink500))
            }
            .frame(width: 200, height: 200)
            .clipShape(.rect(cornerRadius: SoundChexTheme.radiusLargeArt))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)

            VStack(spacing: 6) {
                Text("Album")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(SoundChexTheme.ink500)
                Text(album.title).font(.title3.bold()).foregroundStyle(SoundChexTheme.ink100)
                    .multilineTextAlignment(.center)
                Text(metaLine).font(.subheadline).foregroundStyle(SoundChexTheme.ink500)
            }

            HStack(spacing: 12) {
                // Primary: accent Play pill.
                Button {
                    playback.play(album.tracks)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(SoundChexTheme.accent, in: .capsule).foregroundStyle(.white)
                }

                // Secondary: 44px bordered circles for shuffle and download.
                circleButton(system: "shuffle") {
                    if !playback.isShuffled { playback.toggleShuffle() }
                    playback.play(album.tracks)
                }
                circleButton(system: "arrow.down") {
                    switch downloads.downloadAll(album.tracks) {
                    case .started(let n): flash("Downloading \(n) songs…")
                    case .insufficientSpace: flash("Not enough free space.")
                    case .nothingToDo: flash("Already downloaded.")
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4)

            if let batchMessage {
                Text(batchMessage).font(.caption).foregroundStyle(SoundChexTheme.ink500)
            }
        }
        .padding(.top, 12)
    }

    /// A 44px bordered circle icon button — the secondary detail-screen action
    /// shape (shuffle, download) from the spec.
    private func circleButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(SoundChexTheme.ink200)
                .overlay(Circle().stroke(SoundChexTheme.base600, lineWidth: 1))
        }
    }

    /// "Artist · 2019 · 12 songs" — the "·"-joined meta line from the spec,
    /// skipping any part that is missing.
    private var metaLine: String {
        var parts = [album.artist]
        if let year = album.tracks.first?.meta?.releaseYear { parts.append(String(year)) }
        parts.append("\(album.tracks.count) song\(album.tracks.count == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
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
