# Changelog

All notable changes to the SoundChex iOS app. Versions use SemVer with a
music-themed name per minor release â see `Plans/Versioning.md`.

## 0.8.0 “Reprise” — 2026-09-21

### Changed
- **The book reader is now reflowable, and reads EPUB too** (S-295). The server
  parses each book to text and the app renders a Kindle-style reader from it —
  adjustable font size, serif/sans, and a light/sepia/dark page, resuming to where
  you left off. Because the text comes parsed from the server, **EPUB now works**
  (no on-device unzipping) and a **scanned PDF reads via its OCR text**, the same
  as any other book. Replaces the PDF-only page viewer from 0.7.0.
- **Books show their pictures inline** — a book's illustrations (and a scanned
  page's image) are placed with the text on their page, the same text-and-images
  read the desktop reader gives, so an illustrated or scanned book no longer loses
  its images to the text-only reflow.

## 0.7.0 âCadenceâ â 2026-09-21

### Added
- **Video subtitles** (S-160) â a captions button on the video player lists the
  film's subtitle tracks; choosing one shows it over the video, synced to
  playback. Tracks and their WebVTT come from the new token-authed subtitle API.
  (The line is parsed and drawn as an overlay rather than merged into the stream,
  which keeps it working over the auth-headed remote video.)
- **Book reader â PDF** (S-161) â books now open a reader (a **Read** button on a
  book's page). **PDFs** render with PDFKit, resume to the page you left off, and
  report progress back to the server. **EPUB** shows a "coming soon" for now â it
  needs an archive dependency the app doesn't carry yet; a follow-up.

## 0.6.0 âRefrainâ â 2026-09-21

### Added
- **Multiple server addresses, fastest wins** â the same server can be reached at
  a fast LAN address at home and a tunnel/relay hostname away from it. The app now
  races the known addresses on launch (against the server's `/up` health route)
  and uses the fastest that answers â the ~20ms local path at home, the tunnel
  elsewhere â instead of being pinned to whichever address was typed at sign-in.
  Add alternates under **Settings â Server â Address**, where the one in use is
  marked and a **Re-check connection** re-runs the race after moving between home
  and away. One token is shared across a server's addresses. (S-162)
- **Resumable downloads** â a large download interrupted midway (the app killed,
  the network dropped) now resumes from where it stopped rather than starting
  over, using the background `URLSession`'s resume data. Interrupted transfers
  pick up automatically on the next launch. (S-159)
- **Crash & diagnostic reporting to the server** (S-293) â the app now reports to
  your server's **Device Reports** (the admin page the old app used), so a
  device-only problem is diagnosable from the server instead of by pulling logs
  off the phone. Crash reports are collected via **MetricKit** (`MXCrashDiagnostic`,
  delivered on the next launch after a crash â no third-party SDK) and sent
  automatically; a recent app-log buffer rides along with every report. Verbose
  logging runs through `AppLog` (every network call, playback load, lifecycle
  event), and **Settings â Send diagnostics** posts the current logs on demand.
  Reports carry no media or account details, and the endpoint is unauthenticated
  by design so a broken session can still be reported.

## 0.5.1 âBridgeâ â 2026-09-21

### Fixed
- **Crash on playing any song** â the app trapped (`EXC_BREAKPOINT`) as soon as a
  track started. The lock-screen artwork code built the `MPMediaItemArtwork`
  request-handler closure inside the `@MainActor` `PlaybackController`, so it
  inherited main-actor isolation; MediaPlayer invokes that closure on its own
  background queue to render the bitmap, and the Swift concurrency runtime traps
  when a main-actor closure runs off-main. The artwork is now built by a
  `nonisolated` factory whose `@Sendable` closure captures only the (Sendable)
  `UIImage`, so it runs safely on any thread. (This fix was written for 0.4.2 but
  a merge mistake left it out of the shipped build; it is really in now.)

## 0.5.0 âBridgeâ â 2026-09-21

### Changed
- **The Music space is redesigned Spotify-style** (S-288), keeping SoundChex's
  own red accent and palette â only the Music tab changes; Home, Movies, Shows
  and Books stay as they were.
  - **Music landing** â the tab opens on a Recents surface (an Albums grid and a
    circular-artist shelf) with a **filter-chip row** (Playlists / Albums /
    Artists / Songs). A chip narrows to one kind with a clear-Ã; no chip shows
    the recents. This replaces the old fixed pill sub-nav.
  - **Now-playing sheet** â a fixed Spotify-style layout: big art, left-aligned
    title, an accent scrubber, a 64px play button, and **Lyrics** and **Queue**
    raised as their own sheets from a bottom bar (no longer one long scroll). The
    header reads "PLAYING FROM <album>".
  - **Album & artist detail** â a cover/banner that fades into the list, a
    **dominant round accent Play button**, and the playing track marked with an
    animated equalizer and an accent title. The artist page gains a hero banner
    and a **Popular** list.
  - **Track rows** everywhere show the equalizer + accent title on the track
    that is playing. Artist artwork is now circular, album/song/playlist art a
    rounded square, per the reference designs.

Note: there is no "save/like" concept in the app yet, so the player uses the
existing **Download** control where Spotify shows a heart; a real favourite would
need a server endpoint (out of scope here).

## 0.4.2 âInterludeâ â 2026-09-21

### Fixed
- **Lock-screen & Control Center artwork** â the cover now shows while music
  plays. `updateNowPlayingInfo()` set the title, artist and timing but never
  `MPMediaItemPropertyArtwork`, so the lock screen showed a blank square. The
  cover is loaded from the shared disk cache (so it appears instantly and works
  offline) and attached, refreshing when the track changes. A track change that
  lands mid-load drops the stale image rather than painting it onto the new
  track (S-290).

## 0.4.1 âInterludeâ â 2026-09-17

### Fixed
- **Playlist cover upload failed** â setting a cover while creating or editing a
  playlist didnât attach the image. Two causes: the multipart body was sent via
  `httpBody` (now `upload(from:)` + explicit Content-Length), and a picked photo
  was uploaded full-resolution (2â5 MB), over the serverâs upload limit. Covers
  are now **downscaled to 1000px** before upload (~a few hundred KB), which a
  playlist cover never needs to exceed. A cover failure also no longer discards
  the playlist â itâs saved; only the image is skipped, with a note.
- **Playlist covers now render as clean squares** in the list â the cover view
  is intrinsically 1:1 and clips its contents, so a landscape/portrait image or
  an odd mosaic no longer distorts a cardâs shape.
- Removed the build number from the Settings version (shows `0.4.1 âInterludeâ`).

## 0.4.0 âInterludeâ â 2026-09-17

### Added
- **Persistent header on every page** â a search field and the account button
  now sit in a bar at the top of Home, Music, Movies, Shows and Books. Tapping
  search opens a full-screen search overlay; the account button opens Settings.
  The dedicated Search tab is removed (its function moved into the header).
- **Playlists in Music** â a new **Playlists** pill alongside Songs / Albums /
  Artists, with Spotify/Apple-style playlist management:
  - Create, rename, and describe playlists; set a **cover image** (or fall back
    to a 2Ã2 mosaic of the tracks' covers).
  - A big-cover detail page with a Play / Shuffle header and total duration.
  - **Drag-to-reorder** and swipe-to-remove tracks, persisted to the server.
  - Delete a playlist (the songs stay in your library).

### Changed
- Home no longer floats the account avatar over the hero â the header carries it.

## 0.3.0 âCrescendoâ â 2026-09-17

### Added
- **Download all** â a batch download on an album (reusable for the whole
  library) that queues every not-yet-stored track, gated on free space: it
  refuses when the device is under a 1 GB floor
  (`volumeAvailableCapacityForImportantUsage`) and reports back whether it
  started, had nothing to do, or lacked space. (IOS-05c)
- **Library delta sync** â after the first full catalogue fetch, each launch
  sends the server's last `synced_at` and the ids it holds to
  `POST /api/v1/library/delta`, then merges only changed items and drops
  `removed_ids` (deletions and tightened rating caps alike) instead of
  re-downloading the whole catalogue. Falls back to a full fetch if the server
  rejects the baseline; the baseline is cleared with the cache on
  sign-out / change-server. (IOS-05c, was IOS-12)

## 0.2.0 âOvertureâ â 2026-09-16

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
