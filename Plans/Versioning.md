# Versioning

SoundChex uses **SemVer** (`MAJOR.MINOR.PATCH`) with a personality: every
**minor** release gets a **music-themed name**, and that name holds for the
whole minor — **it changes only at the next minor bump**, never on a patch.

- **PATCH** (`0.17.00 → 0.17.01 → 0.17.02 …`) — fixes, no new features.
  **Same name.** All of `0.17.x` is "Bridge"; the name does not change again
  until `0.18.0`.

  The patch is written **zero-padded to two digits** (S-380), so a version is
  a fixed width — `0.17.03`, not `0.17.3`. Each field is still just a number,
  so Apple accepts it and it sorts correctly. A minor or major bump resets the
  patch to `0`, written plainly: `0.18.0`, not `0.18.00`.
- **MINOR** (`0.4.x → 0.5.0`) — new features. **New name** (the next unused one).
- **MAJOR** (`0.x → 1.0.0`) — the first stable, feature-complete release.

So one name per minor, however many patches that minor collects: the name is
keyed on `MAJOR.MINOR` alone (see `AppRelease.name(for:)`), so `0.4.0` and
`0.4.9` both read "Interlude". While pre-1.0 the API and shape can still move; a
minor bump is our "meaningful step forward", a patch our "made it better".

## The names

Music terms, roughly in order of a piece: an overture opens, it builds, it
resolves. Pick the next unused one at each minor bump.

| Version | Name | What it was |
|---------|------|-------------|
| 0.2.0 | **Overture** | The first native Swift iOS app: sign-in, browse, playback, downloads/offline, playlists, admin, detail screens, lyrics. |
| 0.3.0 | **Crescendo** | Batch "download all" gated on free space, and incremental library delta sync (`/library/delta`) instead of a full re-fetch each launch. |
| 0.4.0 | **Interlude** | Persistent search + account header on every page (Search tab removed); a Playlists pill in Music with Spotify-style create/edit/reorder/cover playlists. |
| 0.8.0 | **Reprise** | |
| 0.9.0 | **Coda** | |
| 0.10.0 | **Verse** | |
| 0.12.0 | **Ledger** | |
| 0.13.0 | **Anchor** | |
| 0.14.0 | **Folio** | |
| 0.15.0 | **Porter** | |
| 0.16.0 | **Tether** | Offline playback fixes, search kebab, now-playing indicators, resuming downloads. |
| 0.17.0 | **Bridge** | Playlist duplicate warning, the sheet pinned to the song it was opened for, remove-from-playlist in the kebab, scrolling titles. |
| 0.18.0 | Refrain | _(next)_ |
| 0.19.0 | Cadence | |
| 1.0.0 | Encore | The first stable release. |

Names are **keyed on `MAJOR.MINOR` in `AppRelease.names`**, and that map is what
Settings reads. A name written only in the CHANGELOG is not shipped: the map
stopped at 0.8 for a while and Settings showed a bare number from 0.9 to 0.17
while the release notes called those releases Coda, Verse, Ledger and the rest
(S-380). Add the entry when the minor is bumped, not afterwards.

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

## The name bank

There is no shortage of names — music terminology gives 100+ good ones before
we'd feel constrained. Pick the next **unused** name at each minor bump: take it
from the recommended sequence unless a name fits the release's character better,
then move its row up into the table above and cross it off here.

`Encore` is reserved for **1.0.0** — don't spend it early.

### Recommended sequence (next up)

After 0.4.0 "Interlude": Bridge → Refrain → Cadence → Vamp → Resonance → Cascade → _(then dip into
the pool below)_ → **Encore (1.0.0)**.

### The pool, by category

**Structure / form** — Prelude, Intro, Interlude, Bridge, Refrain, Chorus,
Verse, Hook, Coda, Outro, Reprise, Movement, Passage, Cadenza, Cadence, Segue,
Vamp, Breakdown, Drop, Build, Intermezzo, Postlude, Motif, Theme, Variation,
Development, Recapitulation, Exposition, Interval.

**Dynamics / expression** — Diminuendo, Forte, Fortissimo, Pianissimo,
Sforzando, Accent, Swell, Sustain, Legato, Staccato, Marcato, Tenuto, Rubato,
Espressivo, Dolce, Vivace, Grave, Tremolo, Vibrato, Glissando, Portamento,
Fermata, Attack, Release, Decay, Resonance.

**Tempo** — Largo, Adagio, Andante, Moderato, Allegro, Allegretto, Presto,
Prestissimo, Accelerando, Ritardando, Lento, Grazioso, Con Brio, Agitato.

**Harmony / theory** — Harmony, Melody, Counterpoint, Chord, Triad, Octave,
Fifth, Third, Unison, Consonance, Dissonance, Resolution, Modulation, Transpose,
Arpeggio, Scale, Mode, Tonic, Dominant, Progression, Voicing, Inversion,
Suspension.

**Rhythm / time** — Tempo, Meter, Measure, Downbeat, Upbeat, Backbeat,
Syncopation, Groove, Pulse, Swing, Shuffle, Polyrhythm, Ostinato, Riff, Pattern,
Loop, Beat.

**Works / genres** — Sonata, Symphony, Concerto, Rhapsody, Nocturne, Serenade,
Ballad, Étude, Fugue, Canon, Requiem, Anthem, Hymn, Lullaby, Fantasia, Toccata,
Suite, Aria, Cantata, Elegy, Waltz, Fanfare, Berceuse, Barcarolle, Caprice,
Impromptu, Divertimento, Scherzo, Minuet, Gigue, Sarabande, Chaconne,
Passacaglia.

**Instruments / voice / gear** — Timbre, Register, Falsetto, Soprano, Alto,
Tenor, Baritone, Bass, Treble, Reverb, Echo, Delay, Phaser, Distortion,
Overdrive, Fader, Mixer, Console, Amplifier, Waveform, Frequency, Oscillator,
Filter, Envelope.

**Notation / marks** — Clef, Staff, Ledger, Sharp, Flat, Natural, Rest, Tie,
Slur, Beam, Key, Signature, Notehead, Stem, Barline, Repeat, Segno.

**Atmospheric / evocative** — Reverie, Cascade, Wavelength, Amplitude, Tone,
Accord, Chime, Sonic, Aural, Ambience.

> Keep this in step with `Sources/DesignSystem/AppRelease.swift`, whose
> `names` map must gain a `minor → name` row for each version actually shipped —
> the pool here is the menu, that map is what the app displays.
