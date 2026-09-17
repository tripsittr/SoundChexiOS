# iOS App Issues

Tracking for the native Swift iOS client. Same convention as the server repo's
`Documentation & Planning/Issues.md`: every feature, fix and bug gets an entry
before the work starts, and entries move **In progress → Open → Deferred → Done**
without being deleted — a decision not to do something is worth as much as a fix.

Prefix `IOS-` to keep these distinct from the server's `S-` ids.

## Background

The iOS client was a Tauri WebView shell wrapping the remote Laravel web app.
Offline on iOS fought the platform at every turn — WebKit drops the service
worker on cold launch, the `tauri://` and server origins have separate storage,
and offline navigation could not use real page loads. After a long grind
(catalogue-to-disk, offline-shell chrome reconstruction, in-place navigation) the
decision was made to **rebuild iOS natively in Swift/SwiftUI against the JSON
API**. Android will follow natively; **desktop (macOS/Windows/Linux) stays
Tauri**. This supersedes the server repo's S-107 / S-06 / S-07 / S-144 / S-145
offline work *for iOS* — those remain the desktop/web story.

The API case for this split is in the server repo's `NativeClients.md`.

## In progress

| ID | What | Notes |
|----|------|-------|
| IOS-01 | Project scaffold + online browse + playback | The spine: XcodeGen project, token sign-in (profile picker + PIN), library browse for all four types, search, AVPlayer playback with a now-playing bar, background audio, lock-screen controls, resume. Builds clean on the simulator. **Done in the first commit; kept In progress until run on a device.** |

## Open

| ID | What | Notes |
|----|------|-------|
| IOS-04 | Detail screens | Album → track list, artist → albums, show → seasons/episodes, film/book detail. `/api/v1/library` already carries parent_id and the metadata; a per-item detail endpoint is optional (see IOS-13). |
| IOS-17b | Admin: item edit, users, upload | Dashboard is done (IOS-17a). Remaining admin slices, each needing its own `auth:sanctum` admin API: **view/edit a media item** (metadata + artwork), **user + profile management** (list/add/remove users; create/rename/PIN/cap profiles), and **upload / add media**. |
| IOS-18 | Full visual redesign completion | Home hero+rails, palette, poster scrim, dark bars done (this PR). Still to match: detail screens, the now-playing full-screen sheet, the music sub-nav pills, browse grid polish, and the header treatment. Reference `Plans/DesignSpec.md`. |
| IOS-05b | Offline: full catalogue browse | Per-item downloads + offline playback are done (IOS-05a). Still to do: mirror `/api/v1/library` to a local store so the *whole* catalogue browses offline (not just downloads), and gate a "download all" on free space. |
| IOS-06b | Resumable downloads + "download all" | Background transfers work (IOS-06a); still to add resuming a *partial* file after a kill, and album/library batch download with a free-space gate. |
| IOS-07 | Video playback | Films and episodes via `AVPlayerViewController` (or a custom player) — the stream endpoint already serves video with Range. Picture-in-picture, subtitles (needs an API subtitle endpoint — currently session-only). |
| IOS-08 | Book reader | EPUB/PDF rendering. The server's reader routes are session-only; needs API equivalents for text/contents/annotations, or render from the downloaded file. Large; likely deferred behind audio + video. |
| IOS-10 | Change server | Settings has sign-out and profile switch; still needs a "change server" flow (currently only via sign-out + new address). |
| IOS-20 | Shuffle + repeat | Transport controls in the now-playing page and bar. Player supports a queue; add shuffle/repeat modes. |
| IOS-11 | Multiple server addresses / fast-route race | The web connect screen raced a LAN address against the relay. A native app should prefer a fast local address when reachable and fall back to the tunnel — the same 20ms-vs-700ms problem. |
| IOS-12 | Library delta sync | Use `GET /api/v1/library/delta` to keep the local mirror current instead of a full re-fetch each launch. Depends on IOS-05's store. |
| IOS-13 | Item-detail JSON endpoint (server) | Optional. `/api/v1/library` carries most of what a detail screen needs; a dedicated endpoint would add related items, people, skip markers. Build only if IOS-04 needs more than the mirror holds. |
| IOS-14 | Artwork caching | `AsyncImage` re-fetches; add a disk cache so covers are instant on scroll and available offline. |

## Deferred

| ID | What | Notes |
|----|------|-------|
| IOS-15 | Android native client | Same native approach in Kotlin/Compose against the same API, once the iOS shape is proven. The API built for iOS (profiles, token-authed stream, progress, search) is shared. |
| IOS-16 | Bundle Tailscale | Same conclusion as the server repo's S-33: a real tunnel needs a Network Extension entitlement; not worth it unless the app is distributed to other people. |

## Done

| ID | What | When | Notes |
|----|------|------|-------|
| IOS-02 | Device signing | 2026-09-16 | Team `7GSWB72PH6` + bundle id `app.soundchex.ios` + automatic signing captured in `project.yml` (so `xcodegen generate` doesn't wipe them). Builds and installs to iPhone 3000. |
| IOS-P | Full-page profile picker | 2026-09-16 | Replaced the sheet with a full-screen "Who's listening?" page — a grid of Netflix-style coloured avatar tiles (profile colour + initial, or avatar image), PIN alert for locked profiles, "Use a different account" to back out. Server `POST /api/v1/profiles` now returns `color`/`initial`/`avatar_url`. |
| IOS-D | Visual redesign to match the web theme (partial) | 2026-09-16 | Exact palette in `SoundChexTheme` (tokens.css hex), home screen rebuilt as hero + horizontal poster rails, poster scrim overlay, dark tab/nav bars. `Plans/DesignSpec.md` captures the full spec. Remaining surfaces tracked as IOS-18. |
| IOS-B1 | Fix "no audio" playback | 2026-09-17 | The stream URL carried the token as a query param, which Sanctum ignores → every stream 401'd (playback started, no audio). Now the bearer token is attached to the AVURLAsset as an Authorization header (survives range requests / seeks). |
| IOS-B2 | Library "server couldn't load" | 2026-09-17 | Fixed defensive decoding: `MediaItem` tolerates any missing/malformed field (a bad artwork URL no longer fails the whole catalogue); corrected the `parent_id` key mapping under `.convertFromSnakeCase`; error messages now name the real cause. |
| IOS-09 | Now-playing full-screen page | 2026-09-17 | Tap the bar → full-screen player: large artwork, working scrubber, transport, and an "Up next" queue. |
| IOS-Q | Queue, swipe & kebab actions | 2026-09-17 | Swipe right → add to queue, swipe left → play next; a ⋯ kebab on each row with Play next / Add to queue. `playNext`/`addToQueue`/`upNext` on the player. (Add-to-playlist joins these with IOS-19.) |
| IOS-S | Settings + profile switch access | 2026-09-17 | Account button on Home → Settings: server address, Switch profile, Sign out. |
| IOS-SW | Profile switch without sign-out | 2026-09-17 | Account (Laravel login) vs profile (who's using it) are distinct: switching profile is no sign-out, no password. Server `GET /profiles/mine` + `POST /profiles/switch` issue a fresh profile token from the current one (PIN only where locked); the signed-in view is keyed on an identity generation so it reloads for the new profile. |
| IOS-BAR | Now-playing bar covered the tab bar | 2026-09-17 | The bar now insets each tab's content so it docks above the system tab bar instead of over it. |
| IOS-NPC | Now-playing controls | 2026-09-17 | Shuffle and repeat (off/all/one) working in the player; a persistent download icon and a ⋯ kebab on the now-playing page. |
| IOS-LYR | Lyrics | 2026-09-17 | Now-playing shows a Lyrics section only when the song has lyrics. Server `GET /items/{id}/lyrics` + `LyricsService` fetch/cache from LRCLIB (free, no key). Genius/Musixmatch can be added behind the same service. |
| IOS-ICON | App icon, accent, dark launch | 2026-09-17 | SoundChex headphones+waveform icon (1024, no alpha) in Assets.xcassets; accent red; base-900 launch ground; display name "SoundChex"; dark mode. |
| IOS-05a | Downloads + offline playback | 2026-09-17 | `DownloadStore`: background URLSession downloads a track's stream to disk (self-describing JSON sidecars, excluded from backup); the player prefers the local file for any stored track, so downloads play offline. Download button (progress ring → green check), kebab Download/Remove, and a Downloads screen (Settings → Library) that plays the whole list. |
| IOS-06a | Background downloads | 2026-09-17 | Background `URLSession` keeps a transfer going while suspended and reattaches on launch. (Partial-file resume + batch "download all" is IOS-06b.) |
| IOS-19 | Playlists | 2026-09-17 | Add-to-playlist from the kebab and the left swipe → a sheet that picks an existing playlist or creates one. A Playlists screen (Settings → Library) lists them and plays a playlist's tracks as a queue. New server API: `auth:sanctum` `GET/POST /playlists`, `GET/DELETE /playlists/{id}`, `POST/DELETE /playlists/{id}/items` (account-scoped Collections, gated per track). |
| IOS-17a | Admin dashboard | 2026-09-17 | Read-only admin dashboard (Settings → Admin, shown only for an admin profile): library counts, activity (plays/accounts/profiles), most-played. Server `GET /api/v1/admin/stats` behind `EnsureApiAdmin`; `/me` returns `is_admin`. |
