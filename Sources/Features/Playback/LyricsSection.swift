// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 SoundChex

import SwiftUI

/// Lyrics for the current track — synced and scrolling when the server has
/// timing, a plain block otherwise (S-300).
///
/// Asks the lyrics endpoint (`GET /api/v1/items/{id}/lyrics`), which returns the
/// plain words and, when available, time-synced LRC text. With timing, the lines
/// scroll and the current one is highlighted against the player position, and a
/// line can be tapped to seek to it. Without timing, the words are shown as a
/// static, selectable block. If the server has nothing, nothing is shown — no
/// empty "no lyrics" state, per the design.
struct LyricsSection: View {
    @Environment(Session.self) private var session
    @Environment(PlaybackController.self) private var playback
    let item: MediaItem

    @State private var lyrics: APIClient.Lyrics?
    @State private var synced: [LRCLine] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if !synced.isEmpty {
                SyncedLyricsView(lines: synced, position: playback.position) { time in
                    playback.seek(to: time)
                }
                .padding(.top, 36)
            } else if let plain = lyrics?.plain, !plain.isEmpty {
                plainLyrics(plain)
            } else if isLoading {
                // Hold the space while the request is in flight. Rendering
                // nothing let the sheet collapse to a sliver until the words
                // arrived (S-338).
                ProgressView()
                    .tint(SoundChexTheme.ink500)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Text("No lyrics for this track.")
                    .font(.system(size: 15))
                    .foregroundStyle(SoundChexTheme.ink500)
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .task(id: item.id) {
            isLoading = true
            lyrics = nil
            synced = []
            lyrics = try? await session.api?.lyrics(itemID: item.id)
            synced = LRCLine.parse(lyrics?.synced)
            isLoading = false
        }
    }

    private func plainLyrics(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lyrics")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(SoundChexTheme.ink500)

            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(SoundChexTheme.ink200)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 36)
    }
}

/// One timed lyric line: the time it starts and its words.
struct LRCLine: Identifiable, Hashable {
    let id = UUID()
    let time: Double
    let text: String

    /// Parses LRC text — lines of the form `[mm:ss.xx] words` — into timed lines,
    /// sorted by time. A single line may carry several timestamps (`[..][..]`);
    /// each becomes its own entry. Returns [] for nil, empty, or untimed input,
    /// which signals the caller to fall back to the plain view.
    static func parse(_ lrc: String?) -> [LRCLine] {
        guard let lrc, !lrc.isEmpty else { return [] }

        // [mm:ss], [mm:ss.xx] or [mm:ss.xxx]. Captures minutes, seconds, frac.
        let tag = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/

        var lines: [LRCLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let matches = line.matches(of: tag)
            guard !matches.isEmpty else { continue }

            // The words are whatever follows the last timestamp on the line.
            let words = line[matches.last!.range.upperBound...]
                .trimmingCharacters(in: .whitespaces)

            for m in matches {
                let minutes = Double(m.output.1) ?? 0
                let seconds = Double(m.output.2) ?? 0
                let frac = fraction(m.output.3)
                lines.append(LRCLine(time: minutes * 60 + seconds + frac, text: words))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    /// A fractional-second string ("5", "50", "500") as a 0–1 value, honouring
    /// its digit count (centiseconds vs milliseconds).
    private static func fraction(_ substring: Substring?) -> Double {
        guard let substring, let value = Double(substring) else { return 0 }
        return value / pow(10, Double(substring.count))
    }
}

/// The scrolling, highlighted synced lyrics. The line for the current position is
/// emphasised and kept in view; tapping a line seeks to it.
private struct SyncedLyricsView: View {
    let lines: [LRCLine]
    let position: Double
    let onSeek: (Double) -> Void

    /// The index of the line that should be highlighted for `position` — the last
    /// line whose start time has passed.
    private var activeIndex: Int? {
        guard let idx = lines.lastIndex(where: { $0.time <= position + 0.25 }) else {
            return lines.isEmpty ? nil : 0
        }
        return idx
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lyrics")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(SoundChexTheme.ink500)

            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeIndex
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 18, weight: isActive ? .bold : .regular))
                            .foregroundStyle(isActive ? SoundChexTheme.ink100 : SoundChexTheme.ink400)
                            .opacity(isActive ? 1 : 0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .id(index)
                            .onTapGesture { onSeek(line.time) }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: activeIndex)
                .onChange(of: activeIndex) { _, newIndex in
                    guard let newIndex else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
