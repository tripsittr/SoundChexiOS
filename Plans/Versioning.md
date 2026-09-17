# Versioning

SoundChex uses **SemVer** (`MAJOR.MINOR.PATCH`) with a personality: every
**minor** release gets a **music-themed name**. Patches keep their minor's name.

- **PATCH** (`0.2.0 → 0.2.1`) — fixes, no new features. Same name.
- **MINOR** (`0.2.0 → 0.3.0`) — new features. New name.
- **MAJOR** (`0.x → 1.0.0`) — the first stable, feature-complete release.

While pre-1.0 the API and shape can still move; a minor bump is our "meaningful
step forward", a patch our "made it better".

## The names

Music terms, roughly in order of a piece: an overture opens, it builds, it
resolves. Pick the next unused one at each minor bump.

| Version | Name | What it was |
|---------|------|-------------|
| 0.2.0 | **Overture** | The first native Swift iOS app: sign-in, browse, playback, downloads/offline, playlists, admin, detail screens, lyrics. |
| 0.3.0 | Crescendo | _(next)_ |
| 0.4.0 | Interlude | |
| 0.5.0 | Bridge | |
| 0.6.0 | Refrain | |
| 1.0.0 | Encore | The first stable release. |

## Where the version lives

- **iOS app** — `project.yml`: `MARKETING_VERSION` (the SemVer) and
  `CURRENT_PROJECT_VERSION` (the build number, bumped every build sent to a
  device or TestFlight). The name is shown in Settings alongside the number.
- **Server / desktop** — `src-tauri/tauri.conf.json` `version`, kept in step at
  each release (they ship together).

## On release

1. Bump `MARKETING_VERSION` (and the name for a minor).
2. Bump `CURRENT_PROJECT_VERSION`.
3. Write the changelog entry.
4. Tag `v0.2.0` on the merge commit.
