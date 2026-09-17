# Plan: Online browse + playback (IOS-01)

The first milestone: a native app that signs in, browses the whole library, and
plays music online. Offline and downloads (IOS-05/06) come after this is solid
on a device. Chosen so the full spine — auth → API → native UI → AVPlayer — is
proven end to end before breadth is added.

## Done in this milestone

- **Project** — XcodeGen (`project.yml` → `SoundChex.xcodeproj`), iOS 17 target,
  Swift 6 strict concurrency, background-audio entitlement, ATS relaxed for
  self-hosted http addresses.
- **Auth** — two-step sign-in: verify credentials + list profiles
  (`POST /api/v1/profiles`), pick a profile (PIN if locked), mint a token
  (`POST /api/v1/tokens`). Token in the Keychain, server address in UserDefaults.
- **Browse** — one `LibraryStore` loads `GET /api/v1/library` once; tabs (Music
  list, Movies/Shows/Books grids, Search) filter it. Artwork via `AsyncImage`
  from the public `/storage` URLs.
- **Playback** — `PlaybackController` (one AVPlayer + queue) streams from the
  token-authed `GET /api/v1/items/{id}/stream` (Range/seek). Now-playing bar,
  lock-screen/Control-Center commands, background audio, resume from
  `GET .../progress`, progress reported every 5s to `POST .../progress`.

## Server API built for this (in the server repo)

All under `/api/v1`, Sanctum-guarded except profiles:
- `POST /api/v1/profiles` — credentials → profile list (unauthenticated,
  throttled like the token endpoint).
- `GET /api/v1/items/{id}/stream` — token-authed streaming with Range.
- `GET|POST /api/v1/items/{id}/progress` — resume position read/write.
- `GET /api/v1/search` — library search (titles, people, dialogue, book text).

## Verify

- Simulator: sign in with a real account, browse each tab, tap a song → it
  plays, the bar shows it, scrubbing seeks, backgrounding keeps audio, force-quit
  and replay resumes position.
- Device: blocked on IOS-02 (signing).

## Next

IOS-03 (server search), IOS-04 (detail screens), then IOS-05 (offline + downloads
— the native answer to why iOS left Tauri).
