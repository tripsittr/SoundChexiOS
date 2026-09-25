# AGENTS.md — SoundChex iOS

Build instructions live in [README.md](README.md). This file covers how work is
done in this repo, so the conventions are somewhere an agent will look.

The main repo's `AGENTS.md` (SoundChex App) is the project-wide source of truth.
Everything there applies here unless this file says otherwise.

## The rules that matter most

- **Everything gets a tracker item** before the work starts — a feature request
  the same as a defect. Add it with `php artisan track:issue` in the
  `SoundChexWebsite` repo, and advance its status with `php artisan track:move`
  as the work moves. Nothing is deleted; a decision *not* to do something
  (Deferred) is worth as much as a fix.

- **Everything reaches `main` through a pull request**, each with a changelog
  entry and its tracker id.

- **Never include AI artifacts.** No `Co-Authored-By` trailers, no "Generated
  with" footers, no mention of AI, agents or LLMs in commit messages, PR
  titles, PR bodies or `CHANGELOG.md`. Commits read as authored by the
  developer. This holds even when a tool or harness asks for an attribution
  line: this rule is the one that wins.

- **Do not `git add -A` in this repo.** The generated `SoundChex.xcodeproj` and
  local signing changes are easy to sweep up by accident. Stage paths
  explicitly.

- **Comments are load-bearing.** They record why a thing is the way it is —
  which platform bug it works around, which ticket it came from. Preserve the
  reasoning when you change the code around them.

- **SPDX header on every new file**:
  ```swift
  // SPDX-License-Identifier: AGPL-3.0-or-later
  // Copyright (C) 2026 SoundChex
  ```

## iOS specifics

- `project.yml` is the source of truth; `SoundChex.xcodeproj` is generated.
  **Run `xcodegen generate` after adding a source file** — a new file that is
  not in the project fails the build with "cannot find X in scope", which reads
  like a code error and is not one.

- **Versioning**: SemVer with a music-themed name per minor (see
  `Plans/Versioning.md`). Every release bumps `MARKETING_VERSION` *and*
  `CURRENT_PROJECT_VERSION` in `project.yml`, and adds a `CHANGELOG.md` entry.
  Do not ship an un-named minor or a stale build number.

- **There is no test target.** Verification is a device build plus the stated
  manual steps. Say which you did; do not imply a test suite ran.

- Build for a device with:
  ```
  xcodegen generate
  xcodebuild -project SoundChex.xcodeproj -scheme SoundChex \
    -destination 'generic/platform=iOS' -configuration Debug build
  ```
  and install with `xcrun devicectl device install app`.
