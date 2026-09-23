# Changelog

All notable changes to the SoundChex iOS app. Versions use SemVer with a
music-themed name per minor release â see `Plans/Versioning.md`.

## 0.13.0 “Anchor” — 2026-09-23

Named for the scrubber finally staying put.

### Fixed
- **The app opens offline** (S-337). Launching with no network — airplane mode,
  out of service, or the server simply down — showed the connection screen
  instead of the downloaded library. Two network calls blocked startup: the
  address race in `Session.restore()`, and `refreshIdentity()` with its
  20-second timeout ahead of the disk cache. The cache is read first now.
- **Search works offline** (S-336). It asked the server first and only filtered
  the cached catalogue if that failed, so every offline search waited out the
  timeout. The device answers from its own catalogue immediately; the server
  refines it when it replies.
- **The scrubber is locked to the song** (S-342). The time observer wrote
  `position` from any tick, including ticks for the track being replaced, so a
  skip could start the next song wherever the last was abandoned. The full
  player also kept its own drag state and never released it on a track change,
  which froze the thumb at the time it was dragged to.
- **Playback is remembered across a close or a crash** (S-342). Pausing,
  backgrounding or being killed records the track and its position; the next
  launch restores that one track where it stopped, paused. Moving between songs
  still always restarts.
- **Reopening the app no longer autoplays** (S-345). The interruption handler
  resumed without checking whether anything had been playing when the
  interruption began, so a paused track could be started by the interruption
  ending.
- **Download All no longer fails most of a playlist** (S-341). Every track was
  handed to URLSession at once; the queue now runs three at a time and retries
  a 5xx, a throttle or a dropped connection with a widening delay. A 404 or 401
  still fails immediately.
- **Download All no longer starts playback** (S-344). The playlist header's
  Play, Shuffle and Download buttons share one List row, where the default
  borderless style lets a tap anywhere fire every button in it.
- **Pushed screens clear the now-playing bar** (S-343). `nowPlayingInset()` was
  applied to tab roots, which a pushed view does not inherit — the last row of
  a playlist, album, artist or show sat under the bar.
- **The lyrics sheet fills its panel** (S-338). While loading, the section
  rendered nothing, so the sheet sized to empty content and painted a sliver.
  It now holds its space with a spinner and says so plainly when a track has no
  lyrics.

## 0.12.2 — 2026-09-22

### Fixed
- **Downloaded songs that played silence** (S-327). A refused request (a track
  whose file is missing on the server answers 404) was stored as the song
  itself: URLSession treats an error body as a successful download, so a 21-byte
  JSON error became the audio file and the item was marked downloaded. Playing
  it gave no sound, a motionless timeline, and a UI that insisted it was
  playing. Downloads now check the status and content type before storing, and
  refuse anything that is not media.
- **Existing bad downloads are cleared on launch**, so a library full of
  unplayable tracks repairs itself; those items can be downloaded again.
- **A stored file that is not media no longer blocks playback** — the player
  falls back to streaming rather than playing a file it cannot decode.

## 0.12.1 — 2026-09-22

### Fixed
- **Skipping back no longer lands mid-song, or on a song that looks finished**
  (S-326). A track change did not clear the last one's position and duration, so
  the bar kept showing where the previous song was skipped at — or showed the
  new track as already over. Songs now always start at the start; only
  audiobooks resume where they stopped, which is what that was for.
- **Skipping sometimes played nothing** (S-326). Loading a track waits on the
  network before playback starts, and a second skip arriving during that wait
  left the older load to seek and play against the track that had just replaced
  it. Each load now knows when it has been superseded and stops.
- **A track that could not play no longer pretends to** (S-326). A failed item
  (an expired token, a file that has moved) left the UI showing playback with no
  audio and a frozen timeline; the failure is now noticed, playback stops, and
  the reason is logged.
- **Play/pause recovers from a stall in one press** (S-326). The button read its
  own flag rather than the player, so when the two disagreed the first press
  only changed the label.
- Reaching the end of the queue with repeat off now stops, rather than leaving
  the bar showing a finished track as playing.

## 0.12.0 “Ledger” — 2026-09-22

### Changed
- **Albums no longer show twice for different editions** (S-308). The library
  groups albums by the server's canonical album key, so "Album" and "Album
  (Deluxe)" / "(Remastered 2016)" — or the same album with different bracket or
  quote styles — collapse into one album with all its tracks, showing the plain
  title. Numbered sequels and volumes ("(Part IV)", "(II)") stay separate, as
  they should. (Pairs with the server's `album_key`.)

## 0.10.0 “Verse” — 2026-09-22

### Added
- **Synced lyrics** (S-300) — when the server has time-synced (LRC) lyrics for a
  track, the Now Playing lyrics panel scrolls and highlights the current line in
  time with the music, and you can tap a line to jump to it. Tracks with only
  plain lyrics still show them as before; tracks with none show nothing. The
  player position now updates four times a second so the highlighted line lands
  on the right words.

## 0.9.0 “Coda” — 2026-09-22

### Changed
- **The reader shows where you are** (S-298) — under the book title, the reader
  now shows the current **page**, the current **chapter**, and a live **reading
  percentage** (e.g. "Page 42 · Chapter 3: Don't Try · 18%"). The chapter carries
  forward from the last heading, so a page mid-chapter still names its chapter,
  and the percentage tracks the actual scroll position so it moves smoothly as you
  read rather than jumping chapter to chapter. Progress is saved as you go.
- **No more "Page N" stacked down the page.** A reflowed book flowed with a bold
  "Page 1 / Page 2 / …" heading atop every screen, which read as jumbled and left
  empty blocks on blank front-matter pages. Those headings are gone; a heading now
  appears only where a real chapter begins. (Server side: S-298.)

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
