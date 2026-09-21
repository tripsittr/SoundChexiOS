# Changelog

All notable changes to the SoundChex iOS app. Versions use SemVer with a
music-themed name per minor release — see `Plans/Versioning.md`.

## 0.4.2 “Interlude” — 2026-09-21

### Fixed
- **Lock-screen & Control Center artwork** — the cover now shows while music
  plays. `updateNowPlayingInfo()` set the title, artist and timing but never
  `MPMediaItemPropertyArtwork`, so the lock screen showed a blank square. The
  cover is loaded from the shared disk cache (so it appears instantly and works
  offline) and attached, refreshing when the track changes. A track change that
  lands mid-load drops the stale image rather than painting it onto the new
  track (S-290).

## 0.4.1 “Interlude” — 2026-09-17

### Fixed
- **Playlist cover upload failed** — setting a cover while creating or editing a
  playlist didn’t attach the image. Two causes: the multipart body was sent via
  `httpBody` (now `upload(from:)` + explicit Content-Length), and a picked photo
  was uploaded full-resolution (2–5 MB), over the server’s upload limit. Covers
  are now **downscaled to 1000px** before upload (~a few hundred KB), which a
  playlist cover never needs to exceed. A cover failure also no longer discards
  the playlist — it’s saved; only the image is skipped, with a note.
- **Playlist covers now render as clean squares** in the list — the cover view
  is intrinsically 1:1 and clips its contents, so a landscape/portrait image or
  an odd mosaic no longer distorts a card’s shape.
- Removed the build number from the Settings version (shows `0.4.1 “Interlude”`).

## 0.4.0 “Interlude” — 2026-09-17

### Added
- **Persistent header on every page** — a search field and the account button
  now sit in a bar at the top of Home, Music, Movies, Shows and Books. Tapping
  search opens a full-screen search overlay; the account button opens Settings.
  The dedicated Search tab is removed (its function moved into the header).
- **Playlists in Music** — a new **Playlists** pill alongside Songs / Albums /
  Artists, with Spotify/Apple-style playlist management:
  - Create, rename, and describe playlists; set a **cover image** (or fall back
    to a 2×2 mosaic of the tracks' covers).
  - A big-cover detail page with a Play / Shuffle header and total duration.
  - **Drag-to-reorder** and swipe-to-remove tracks, persisted to the server.
  - Delete a playlist (the songs stay in your library).

### Changed
- Home no longer floats the account avatar over the hero — the header carries it.

## 0.3.0 “Crescendo” — 2026-09-17

### Added
- **Download all** — a batch download on an album (reusable for the whole
  library) that queues every not-yet-stored track, gated on free space: it
  refuses when the device is under a 1 GB floor
  (`volumeAvailableCapacityForImportantUsage`) and reports back whether it
  started, had nothing to do, or lacked space. (IOS-05c)
- **Library delta sync** — after the first full catalogue fetch, each launch
  sends the server's last `synced_at` and the ids it holds to
  `POST /api/v1/library/delta`, then merges only changed items and drops
  `removed_ids` (deletions and tightened rating caps alike) instead of
  re-downloading the whole catalogue. Falls back to a full fetch if the server
  rejects the baseline; the baseline is cleared with the cache on
  sign-out / change-server. (IOS-05c, was IOS-12)

## 0.2.0 “Overture” — 2026-09-16

The first native Swift iOS app, replacing the Tauri web mirror on iOS (WebKit
dropped the service worker on a cold app close, breaking offline).

### Added
- Token sign-in with the profile picker and PIN, and profile switching without
  signing out.
- Library browse for music, movies, shows and books; search; detail screens.
- AVPlayer playback with a now-playing bar and full-screen page, background
  audio, lock-screen controls, resume, shuffle and repeat, and lyrics.
- Video playback with Picture in Picture.
- Downloads and offline browse (background `URLSession`, self-describing
  sidecars, local-file playback).
- Playlists, and an admin panel (dashboard, item edit, profile management,
  scan).
