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
| IOS-02 | Device signing | `project.yml` has an empty `DEVELOPMENT_TEAM`; set it (or configure automatic signing) so the app builds to a real iPhone. Provisioning profile, bundle id `net.soundchex.ios`. Until then the app runs only in the Simulator. |
| IOS-03 | Server-side search wiring | `SearchView` filters the local catalogue. Point it at `GET /api/v1/search` (built server-side) for dialogue + book-text coverage, falling back to the local filter offline. |
| IOS-04 | Detail screens | Album → track list, artist → albums, show → seasons/episodes, film/book detail. `/api/v1/library` already carries parent_id and the metadata; a per-item detail endpoint is optional (see IOS-13). |
| IOS-05 | Offline: local catalogue + downloads | The whole reason iOS went native. SwiftData (or a file store) mirror of `/api/v1/library`, per-item downloads to disk, offline browse from the local store, and AVPlayer playing local files when offline. Gated on free space for "download all". Mirrors offline-rebuild scope but done natively. |
| IOS-06 | Background + resumable downloads | `URLSession` background transfers so a film keeps downloading when the app is backgrounded and resumes a partial file. The native answer to the server repo's S-07. |
| IOS-07 | Video playback | Films and episodes via `AVPlayerViewController` (or a custom player) — the stream endpoint already serves video with Range. Picture-in-picture, subtitles (needs an API subtitle endpoint — currently session-only). |
| IOS-08 | Book reader | EPUB/PDF rendering. The server's reader routes are session-only; needs API equivalents for text/contents/annotations, or render from the downloaded file. Large; likely deferred behind audio + video. |
| IOS-09 | Now-playing full-screen sheet | Tapping the bar opens a full player: large artwork, scrubber, queue, shuffle/repeat. The bar is the minimal version. |
| IOS-10 | Sign-out + change server | A settings surface to sign out (revoke the token via `DELETE /api/v1/tokens/current`, clear the Keychain) and switch servers. |
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
| — | (none yet) | | |
