# SoundChex iOS

The native Swift/SwiftUI client for SoundChex, talking to the self-hosted server
over its JSON API. iOS went native (from a Tauri WebView shell) because offline
on iOS fought the platform. Desktop stays Tauri; Android will go native later.

Every feature, fix and bug is tracked in the landing site's admin panel
(`SoundChexWebsite` repo → `/admin` → Tracker), not in a file here.
[CHANGELOG.md](CHANGELOG.md) has what shipped in each release, and
[AGENTS.md](AGENTS.md) has the workflow rules.

## What it does

Browse and search the library, play music and video, and read books. Playlists,
including importing them. Downloads that survive the app closing, so the
library works with no network. AirPlay from the now-playing screen. Lyrics.
Per-profile history and resume points. A small admin area for scanning the
library and checking server stats.

No CarPlay yet — it needs an entitlement granted by Apple.

## Requirements

- Xcode 16+ (built with 26.x), Swift 6 with strict concurrency.
- iOS 17.0 or newer on the device.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is
  generated, not committed as source of truth.

## Getting started

```sh
brew install xcodegen        # once
cd SoundChexiOS
xcodegen generate            # regenerate SoundChex.xcodeproj after editing project.yml
open SoundChex.xcodeproj
```

Run in the Simulator (no signing needed) and sign in with a SoundChex account.
For a device build, set your signing team in `project.yml` (`DEVELOPMENT_TEAM`)
or Xcode's Signing & Capabilities (IOS-02).

From the command line:

```sh
xcodegen generate
xcodebuild -project SoundChex.xcodeproj -scheme SoundChex \
  -destination 'generic/platform=iOS' -configuration Debug build
xcrun devicectl device install app --device <udid> <path-to-SoundChex.app>
```

Re-run `xcodegen generate` after adding a source file. A file that is not in
the project fails the build with "cannot find X in scope", which reads like a
code error and is not one.

There is no test target: verification here is a build plus the device.

## Layout

- `project.yml` — XcodeGen project definition (the source of truth for the
  Xcode project).
- `Sources/App` — app entry, `Session` (auth state), Keychain, logging.
- `Sources/Networking` — `APIClient`, reachability, server-address resolution.
- `Sources/Models` — `MediaItem`, `Playlist`, `Profile`, admin models.
- `Sources/Features` — one directory per area: `Admin`, `Auth`, `Browse`,
  `Detail`, `Downloads`, `Playback`, `Playlists`, `Reader`, `Settings`,
  `Video`.
- `Sources/DesignSystem` — theme tokens matching the web app.
- `Plans/` — design notes, the versioning scheme, and reference material.

## API

The endpoints this app relies on live in the server repo (`SoundChex App`):

- **Auth and identity** — `/api/v1/tokens`, `/api/v1/tokens/current`,
  `/api/v1/me`, `/api/v1/profiles`, `/api/v1/profiles/mine`,
  `/api/v1/profiles/switch`.
- **Catalogue** — `/api/v1/library` for the full mirror and
  `/api/v1/library/delta` for incremental sync, plus `/api/v1/search` and
  `/api/v1/library/shuffle`.
- **Playback** — `/api/v1/items/{id}/stream`, `/api/v1/items/{id}/progress`,
  and the per-item lyrics and subtitle routes.
- **Playlists** — `/api/v1/playlists` and `/api/v1/playlists/imports`.
- **Admin** — `/api/v1/admin/stats`, `/api/v1/admin/scan`,
  `/api/v1/admin/profiles`, `/api/v1/admin/items/{id}`.

The whole catalogue is mirrored to the device, so browse and search run
locally against that copy rather than calling the server per keystroke.

## Licence

SoundChex is **dual-licensed** — **AGPL-3.0-or-later** by default (see
[LICENSE](LICENSE)), or a **commercial licence** for those who can't/won't comply
with the AGPL. Full explanation, the contributor agreement, and the commercial
option are in the main repo:
[LICENSING.md](https://github.com/tripsittr/SoundChex/blob/main/LICENSING.md)
(contact `licensing@soundchex.app`).

All SoundChex platforms share this. Because this is a client people use over a
network to reach their server, any modified, network-hosted build must offer its
users the corresponding source (AGPL §13).
