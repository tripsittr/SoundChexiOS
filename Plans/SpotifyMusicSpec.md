<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Spotify Music Spec — the Music space, Spotify-flavoured

**Status: proposed. Nothing here is built yet.** The design plan for reshaping the
**Music space** to feel like Spotify, keeping SoundChex's own palette and leaving
the rest of the app (Home, Movies, Shows, Books) exactly as
[DesignSpec.md](DesignSpec.md) defines it.

**Grounded in real references.** The owner supplied 23 Spotify screenshots in the
repo-root `references/` folder (`IMG_9547`–`IMG_9569`). This spec describes what
they show; where a detail is called out, the image is cited. Build against the
images, not just this prose.

**The palette does not change.** SoundChex keeps its tokens — base-900 ground,
`accent` **red** (not Spotify green), the ink ramp — from `DesignSpec.md`.
"Spotify-style" means Spotify's *layout and interaction patterns*: filter chips,
rounded-square art on list rows, circular art for artists/people, big section
headings, the art-tinted now-playing bar, art-into-list detail headers. Anywhere
the references show Spotify **green** (active filter chips, the play FAB, download
ticks, the underline under the active tab), we substitute **`accent` red** and its
`accent-hot`. Shapes/radii/ease stay as `DesignSpec.md` sets them.

Scope, agreed with the owner: **(1)** the Music landing, **(2)** the now-playing
sheet, **(3)** album & artist detail, **(4)** track/song rows.

---

## Cross-cutting patterns (from the references)

These recur on every surface; define them once.

- **Art shape by kind.** Albums, playlists, songs, podcasts → **rounded square**,
  radius 4–6px. Artists and people → **circle**. (Library rows `IMG_9547`; search
  recents `IMG_9560`; "Fans Also Like" circles vs "Appears On" squares `IMG_9566`.)
- **Filter chips.** A horizontal, scrollable chip row: an inactive chip is
  base-700 fill / ink-100 text, 999px; an **active** chip is `accent` fill with a
  leading **× to clear** shown as its own round chip (`IMG_9551`, `IMG_9552`).
  Multiple chips can be active. This replaces the current fixed pill sub-nav.
- **List/grid toggle.** A "Recents ↕" sort control on the left and a **list/grid
  icon** on the right of a section header toggles between a list and a
  2–3-column grid of the same items (`IMG_9547` list vs `IMG_9552` grid).
- **Row metadata line.** Under a row/tile title: small ink-400 line like
  "Playlist · Blaze", "Album · 2026", "Song · Artist", with a green→**accent**
  **pin** and **download ↓** glyph inline when they apply (`IMG_9547`).
- **The now-playing bar is tinted from the artwork.** Not a flat base-800 bar —
  its background is a muted colour sampled from the current track's art
  (`IMG_9547` shows a brick-red bar for a warm cover). Fall back to base-800 when
  no colour is available. Rounded 8px, floating just above the tab bar, with a
  1–2px `accent` progress sliver at the bottom.
- **Big section headings.** 22–24px bold ink-100, with "Show all" / "See
  discography" affordances in ink-300 on the right (`IMG_9565`, `IMG_9566`).

---

## 1. The Music landing

**Today:** the Music tab opens onto a fixed pill sub-nav (Songs / Albums /
Artists / Playlists) over a flat list or grid.

**Spotify-style (a "Your Library" surface — `IMG_9547`–`IMG_9552`):**

- **Header:** the account avatar (with a small unread badge when relevant) on the
  left, a title — **"Your Library"** — then a search glyph and a **+** on the
  right. (SoundChex has no "create podcast" etc.; **+** creates a playlist.)
- **Filter chip row** (cross-cutting pattern above): `Playlists` · `Albums` ·
  `Artists` · `Songs`. Tapping one filters what's below to that kind and shows the
  clear-× ; none active shows everything. A second, finer chip set (e.g.
  `Downloaded`) may appear once a kind is chosen (`IMG_9552`).
- **"Recents ↕" bar** with the list/grid toggle on the right.
- **The library items**, as list rows (§4 row shape, but library-item variant:
  art + title + "Kind · Owner" meta line + pin/download glyphs) or as a grid of
  art tiles with a title + meta under each (`IMG_9552`).
- Sort options behind the ↕ (Recents, Recently added, Alphabetical, Creator).

The exhaustive Songs/Albums/Artists browse still exists — it *is* this surface,
filtered. The old always-visible pill bar is replaced by the chip row.

---

## 2. The now-playing sheet

**Today:** big art, a working scrubber, transport, and the up-next queue inline.

**Spotify-style:** the same content as Spotify's player — centred, the queue
behind a control.

- **Top bar:** a down-chevron to dismiss (left), a centred context line
  "PLAYING FROM <ALBUM/PLAYLIST>" (10px uppercase ink-400, 0.16em tracking), a `⋯`
  overflow (right).
- **Artwork:** one large centred rounded square (radius 8–12px), ~screen-width
  minus 48px, soft shadow. No blurred backdrop (that's the Home hero's device).
- **Title block:** left-aligned under the art — title 22px bold ink-100 (1–2
  lines), artist 16px ink-300 tapping through to the artist. A save (＋/heart)
  control on the right.
- **Scrubber:** full-width, 4px track base-600, played fill **`accent`**, thumb
  only while scrubbing. Elapsed (ink-300, left) and remaining (ink-500, right),
  12px tabular.
- **Transport:** one centred row — shuffle (`accent` when on), previous, a **64px
  round ink-100 play/pause with a base-900 glyph** (the references' green FAB,
  here ink-100/accent), next, repeat.
- **Bottom controls:** a compact row — a device/connect glyph, a share glyph, and
  an **"Up next" / queue** button that raises the queue as its own sheet
  (`IMG_9569` shows the queue/credits-style stacked sheet); **Lyrics** open the
  existing `LyricsSection`, Spotify-style as a coloured full-width panel
  (`IMG_9567`/`IMG_9569` bottom).

---

## 3. Album & artist detail

**Album (referenced by the track-detail/credits screens `IMG_9567`, `IMG_9569`):**

- **Header:** the square cover large near the top over a vertical gradient from a
  muted tint of the cover to base-900. On scroll the cover shrinks/fades and the
  album title collapses into the nav bar (scroll-linked). Under the cover: title
  24–28px bold, then a meta line "Album · Artist · Year · N songs, length" in
  ink-400.
- **Action row:** Shuffle, Download, `⋯`, and a **dominant round `accent` Play
  FAB** on the right (the green circle in `IMG_9563`, here red).
- **Track list:** §4 rows, numbered, no per-row art (they share the cover). A
  sticky mini play-button appears in the nav bar once the FAB scrolls away.
- **Credits** ("Show all" → a sheet): "Composition & Lyrics", "Production &
  Engineering", "Performers", each a list of name + role (`IMG_9569`). Populated
  from the app's existing credits data.

**Artist (`IMG_9563`, `IMG_9565`, `IMG_9566`):**

- **Header:** a large **rectangular hero image** (not a circle — Spotify uses a
  banner for the artist's own page), artist name overlaid bottom-left 30–36px
  extrabold, a "verified"-style small mark if applicable, and a monthly-listeners
  / "N songs" sub-line. Circular artist art is for *rails and rows only*.
- **Under the banner:** Follow (pill), shuffle, `⋯`, and the round **`accent`
  Play FAB**.
- **Sections, in order:** **"Popular"** — top tracks as §4 rows with a right-side
  play-count column when available, else library order; **Music / Video / Merch**
  tabs with a green→**accent** underline under the active one (`IMG_9565`);
  **"Featuring"** and **"Appears On"** as square-art shelves; **"Fans Also Like"**
  as **circular** artist shelf (`IMG_9566`). Render only the sections we have data
  for.

---

## 4. Track / song rows

**Today:** a 44px art/number square that flips to a play triangle on hover, title
+ subtitle, duration, and a `⋯` menu.

**Spotify-style (`IMG_9547`, `IMG_9560`, `IMG_9569`):**

- **Layout:** `HStack`, 12px gap, ~56px tall. A **48px rounded-square art
  thumbnail** in contexts that have per-track art (Songs, search, playlists,
  library); album/artist track lists keep the **number** instead. Title 15px
  ink-100 (1 line), a meta line 13px ink-500 — "Artist" or "Song · Artist" — under
  it. A `⋯` on the right (32×44 tap target). A **download ↓** / **explicit E** /
  **video** glyph inline in the meta line where they apply.
- **The playing row:** the current track's title turns **`accent`** and a small
  three-bar **equalizer** animates in place of the art/number. Reduced-motion → a
  static accent bar icon.
- **Duration** stays on album/artist track lists (right, tabular, ink-500) where
  rows are numbered; the songs list leads with art and may drop duration on narrow
  widths.
- **Interaction:** tap plays and sets the queue from the surrounding list (as
  today); `⋯` opens the existing menu (Queue, Add to playlist, Play next, Go to
  album/artist).

---

## Out of scope

- **Palette / accent** — stays SoundChex red; every Spotify-green element becomes
  `accent`.
- **Home, Movies, Shows, Books** — unchanged (Netflix-cinematic per `DesignSpec.md`).
- **New server endpoints** — a client re-layout of data the app already has.
  "Popular"/play-counts and "Fans Also Like" render only if the data exists,
  else those sections are omitted — no server change.
- **Podcasts / Audiobooks / Video / Merch / Blend / Jam / collaborative playlists**
  — Spotify surfaces SoundChex has no equivalent for; omitted, not stubbed.
- **Playlist internal management** — already Spotify-style and shipping; only its
  entry point moves onto the new landing.

---

## Build order (once approved)

Small, compile-verified steps, each its own commit, so the app always builds:

1. **Shared pieces** — the filter-chip row, the art-shape rule, the art-tinted
   now-playing bar, and the §4 row (with the playing-row equalizer). Everything
   else consumes these.
2. **Track rows (§4)** applied across Songs / playlists / search.
3. **Now-playing sheet (§2).**
4. **Album & artist detail (§3).**
5. **Music landing (§1)** — ties it together on the chip row + rows.

Each step: `xcodegen generate` + `xcodebuild` on the iOS 17 simulator to prove it
compiles, a changelog note, and a version bump per `Versioning.md` when the set
lands. The redesign is visual — the owner judges the look in Xcode / on device
against the `references/` images; compilation is what this environment proves.
