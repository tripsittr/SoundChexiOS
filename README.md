# SoundChex iOS

The native Swift/SwiftUI client for SoundChex, talking to the self-hosted server
over its JSON API. iOS went native (from a Tauri WebView shell) because offline
on iOS fought the platform — see `Plans/Issues.md` for the background and the
issue list. Desktop stays Tauri; Android will go native later.

## Requirements

- Xcode 16+ (built with 26.x), Swift 6.
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

## Layout

- `project.yml` — XcodeGen project definition (the source of truth for the
  Xcode project).
- `Sources/App` — app entry, `Session` (auth state), Keychain.
- `Sources/Networking` — `APIClient`.
- `Sources/Models` — `MediaItem`, `Profile`.
- `Sources/Features` — `Auth`, `Browse`, `Playback`.
- `Sources/DesignSystem` — theme tokens matching the web app.
- `Plans/` — issues and plans for this app.

## API

The endpoints this app relies on live in the server repo (`SoundChex App`):
`/api/v1/profiles`, `/api/v1/tokens`, `/api/v1/library`,
`/api/v1/items/{id}/stream`, `/api/v1/items/{id}/progress`, `/api/v1/search`.
