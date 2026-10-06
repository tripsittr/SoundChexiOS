# Changelog

All notable changes to the SoundChex iOS app. Versions use SemVer with a
music-themed name per minor release â see `Plans/Versioning.md`.

## Unreleased

### Changed
- **The fact strip on a film or show page** (#511). Year, certificate and length
  as a row rather than a dot-joined sentence: the pieces are different kinds of
  thing, and running them together made the certificate read as another word
  rather than as a classification. It is boxed now, as the streaming apps show
  it.

  Length reads as **"1h 51m"** rather than "111 min", which is how long a film is
  in every place a person has seen one described. A show's length is its season
  count instead -- nobody asks how many minutes a series runs to.

- **The Play button is white**, and weighted like the one thing somebody came to
  the page to press. The accent colour competed with the poster on a page that is
  mostly artwork and dark surfaces.

## 0.30.07 “Prelude” — 2026-10-05

### Fixed
- **"Recently added" now shows what was recently added** (S-451). It took the
  first twenty items in the catalogue as the server happened to return them —
  and `/api/v1/library` applies no ordering at all, so that was SQLite's own
  row order. Stable, arbitrary, and unchanged when a scan added something,
  which is the one thing the row exists to show.

  The catalogue now carries `added_at` (the server half landed separately), so
  the row sorts by when an item entered the library.

  Not `updated_at`, which was already there and would have been worse than
  arbitrary: an enrichment pass moves it on everything it touches, so the row
  would have filled with whatever the scanner last looked at rather than with
  what is new.

  The date is cached alongside the rest of the item, or the row would be right
  after a fetch and arbitrary again after a relaunch read from disk.

## 0.30.06 “Prelude” — 2026-10-05

### Fixed
- **"Scan for new media" now refreshes the library** (S-450). The button asked
  the server to scan and stopped there, so nothing on the phone changed until
  the next launch — a scan that worked looked exactly like one that had not.

  Two things needed refreshing, not one. The catalogue, and the home shelves:
  "Recently added" comes from a separate endpoint and would otherwise still
  show the library as it was before the scan.

  The reload is a **full fetch**, not a delta. `load()` syncs incrementally
  when it has a baseline, which is right at launch and wrong here — a scan is
  the moment the catalogue has changed most, and a delta keyed on a timestamp
  can miss rows whose `updated_at` the scanner did not move.

  The row says "Scanning…" while it runs, because a scan is not instant and an
  inert-looking button invites a second tap.

  One honest limitation: `/admin/scan` queues the work and returns
  immediately, so there is nothing to await. This gives the server three
  seconds and then reloads. A large library outlasts that, which is the other
  reason the reload is a full fetch — a second tap, or a pull-to-refresh,
  picks up whatever finished later. A completion signal on the server would be
  the real fix.

## 0.30.05 “Prelude” — 2026-10-05

### Changed
- **The bottom bar is drawn, not configured** (S-449). Two earlier attempts
  set `UITabBarAppearance` — the fill, the hairline, a selection indicator —
  and the bar still looked like iOS, because the problem was never the colour.

  On iOS 26 the system tab bar is a **floating rounded capsule, inset from the
  screen edges**. No appearance property changes that: the shape belongs to
  the platform. The web's bar is the opposite —

      position: fixed; inset-inline: 0; bottom: 0;
      border-top: 1px solid var(--color-base-600);

  full width, square corners, flush to the bottom, with a hairline across the
  whole top edge. A capsule cannot be made into that, so `MediaTabBar` draws
  the bar instead of asking UIKit for one.

  The numbers are the stylesheet's rather than an approximation: a 3.25rem
  row, a 1.375rem icon, a 0.625rem label, and the 1.75rem × 2px accent bar on
  the active tab's top edge.

  `TabView` goes with it — the pages are switched on a `MediaTab` instead,
  which also keeps them lazy, something `TabView` never guaranteed.

## 0.30.04 “Prelude” — 2026-10-05

### Changed
- **Four tabs, not five — the nav the web app actually has** (S-449). 0.30.03
  repainted the bars and left their contents alone, which was half the job.

  The media centre has **Home, Watch, Music, Books**. The phone had Home,
  Music, Movies, Shows, Books. Movies and Shows are one *Watch* entry there,
  and the web says why in its own nav:

  > Movies and shows share one entry: choosing what to watch rarely starts
  > with deciding between a film and an episode. The split lives as a sub-nav
  > on that page instead.

  So the phone now matches: a Watch tab, with Movies/Shows as a chip row at
  the top of it. The chips are the same `FilterChipRow` the Music landing
  uses, so the two sub-navs are one control rather than two that resemble
  each other.

  Five was also one short of the ceiling — iOS folds everything past the fifth
  tab into "More", so the next section added would have started hiding things.

- **The active tab is marked at its top edge**, as the web marks it:

      .mobile-tab.is-active::before { top: 0; width: 1.75rem; height: 2px }

  drawn as a 28×2pt selection indicator, which is that measurement at the same
  scale. The web's reasoning holds here too — the eye is already at the top of
  the tab after the icon, and an underline at the bottom would sit under the
  home indicator.

  Generated rather than shipped as an asset, because the accent is a user
  setting and an asset would be stale the moment it changed.

## 0.30.03 “Prelude” — 2026-10-05

### Changed
- **The bars are painted the way the web app paints its own** (S-449). The
  shape stays Apple's — a tab bar at the bottom, a nav bar at the top, where
  iOS users expect them. The finish does not.

  Apple's default is a translucent material that takes its colour from
  whatever scrolls underneath. The media centre uses a flat fill with a
  hairline edge, and that difference is most of what made the two look like
  separate products.

  Matched against `.mobile-tabs` in the web stylesheet rather than
  approximated by eye:

      background: color-mix(in srgb, var(--color-base-800) 94%, transparent);
      border-top: 1px solid var(--color-base-600);

  The tab bar and nav bar already carried the right fill; what they lacked was
  the hairline. `shadowColor` draws it — named for a shadow it has not been
  since iOS 13.

  The now-playing bar kept Apple's `.ultraThinMaterial` and now uses the same
  flat fill, with its top edge corrected from `base-700` to the `base-600` the
  web draws. `base-700` was a shade too dark to read as an edge against the
  bar itself.

  This also retires the Reduce Transparency branch added in 0.29.03: there is
  no longer a blur to opt out of, so the accessibility setting and the default
  now agree rather than diverging.

## 0.30.02 “Prelude” — 2026-10-05

### Fixed
- **The app crashed when opening a show** (S-447). The crash report said
  `signal 5` / `exceptionType 6` — SIGTRAP / EXC_BREAKPOINT, which is a
  *deliberate* trap rather than a memory fault: a Swift runtime precondition
  failed. The attributed thread ran from a dispatch queue, through
  AVFoundation, into our code, into the Swift runtime's failure handler.

  The cause was `MainActor.assumeIsolated` inside an AVFoundation time
  observer. Passing `queue: .main` to `addPeriodicTimeObserver` guarantees the
  main *thread*; it does not put the closure in the main *actor's* isolation
  domain, and `assumeIsolated` **traps** when those differ. AVFoundation makes
  no promise about which domain it calls back from, so the check could fail —
  and failing means the app dies rather than returning a wrong answer.

  Shows are video, so the subtitle observer that did this runs only for the
  thing that was crashing.

  All four `assumeIsolated` call sites are now explicit `Task { @MainActor }`
  hops — asking to be on the main actor rather than asserting it, which is
  what the player's status observer already did correctly:

  - `VideoPlayerView` subtitle observer (the one that crashed)
  - `PlaybackController` periodic time observer — fires four times a second
    for the length of every track, so the most-run closure in the app
  - `PlaybackController` audio-interruption notification
  - `RecentContextsStore` storage-cleared notification

  The hazard was already written down in `OrientationLock`, which avoids it
  for the same reason: *"iOS does not promise to ask this on the main actor,
  and `MainActor.assumeIsolated` traps when that assumption is wrong."*

## 0.30.01 “Prelude” — 2026-09-28

### Added
- **The player puts the artwork beside the controls on a wide screen**
  (S-408, stage 2). Stacked, a square sleeve over a short column of controls
  leaves an iPad in landscape mostly empty and pushes the transport to the
  very bottom of a 13-inch screen — a long way from where a thumb or a cursor
  is.

  Only when the frame is short and wide. An iPad in portrait is regular width
  but tall, and stacking suits it; the decision reads the view's own size, not
  the display's, so Split View gets the right answer.

  The controls keep their own column rather than stretching to fill: a
  scrubber half a metre wide is harder to hit accurately, not easier.

- **Detail and home screens use the space** (stage 3). Album and playlist
  covers grow from 220pt to 300pt at regular width, where a phone-sized sleeve
  looked marooned. The home hero grows from 440pt to 560pt — 440 is most of a
  phone screen and a third of an iPad, which made it read as a banner rather
  than the front of the library.

- **Settings and admin** (stage 4). Settings is a `List` and already adapted.
  The admin dashboard was a single column stretched across the full width,
  putting a label at one edge and its number at the other; it is now capped at
  900pt and centred.

### Fixed
- **The sign-in form is vertically centred on a tall screen.** It sat at the
  top with two thirds of an iPad page empty beneath it.

  This was attempted in 0.30.0 and reverted for pushing the form off-screen
  entirely. The mistake was stretching the content *inside* the scroll view —
  a `ScrollView` sizes to what it holds, so that does nothing useful. Sizing
  the scroll view to its content and centring that works.

### Known gaps
- Stage 5 — deleting `OrientationLock` once every screen has opted in — is
  still open, and should wait until the earlier stages have been used on a
  real iPad.
- None of this has been seen on hardware; it is verified on the 13-inch
  simulator.

## 0.30.0 “Prelude” — 2026-09-28

### Added
- **The app rotates on iPad** (S-408, stage 1). It was locked to portrait on
  every device — a stopgap, because the layouts had no landscape handling at
  all and rotating into them would have shown a visibly broken app.

  An iPad held sideways and refusing to turn reads as broken rather than
  deliberate: it is the orientation a keyboard case puts it in. iPhone stays
  portrait, where landscape is still a compact width and gains nothing.

  The reader stays portrait on both, by the owner's decision: a book is read
  in portrait, and the paginator is single-column and size-driven, so a wider
  page means fewer lines and more page turns.

- **Grids and rails size themselves to the screen.** The library grids were
  already adaptive, so they filled an iPad — with **ten columns of 121pt
  posters** on a 13-inch. Nothing was broken and nothing was browsable either;
  artwork is the point of a library grid.

  The minimum tile width now grows at regular width, which gives four to seven
  poster columns at about 180pt instead. Rails do the same, so a rail on an
  iPad is not a phone's rail with more of it off the edge.

  Keyed on the horizontal size class rather than the device: an iPad in Split
  View is compact and should look like a phone, and a phone in landscape
  should not suddenly grow tiles.

- **The player's artwork uses the space.** It was capped at 360pt and measured
  from `UIScreen.main.bounds` — the whole display, not this view's share of
  it, which is wrong in Split View. It now measures the container and caps at
  520pt where the width allows.

### Known gaps
- Detail and now-playing screens still stack vertically at regular width; a
  side-by-side variant is stage 2.
- Settings, admin and auth are unchanged; they are mostly Lists, which adapt
  on their own, but nothing has been designed for the wider frame.
- The sign-in form sits at the top of a tall iPad screen rather than centred.
  Cosmetic, and an attempt to centre it inside its ScrollView pushed the form
  off-screen, so it was reverted rather than shipped half-working.

## 0.29.06 “Clarity” — 2026-09-28

### Added
- **Films and shows show their synopsis** (S-412). The detail page had the
  tagline, the facts and the credits, but not the paragraph that actually
  tells you what the thing is.

  It sits above the facts table, because the synopsis is what someone reads to
  decide what to watch and the runtime is what they check afterwards.

  The server prefers the owner's own words over TMDB's, so this is not always
  a scraped blurb — a description written in the admin is what the phone
  shows.

## 0.29.05 “Clarity” — 2026-09-28

### Fixed
- **Titles in the Movies, Shows and Books grids were too small.** They were
  `.caption` — 12pt, the size meant for fine print — which read as a footnote
  beside the artwork rather than the name of the thing. Now `.subheadline`,
  with the subtitle a step below it, and they wrap to two lines at the
  accessibility text sizes instead of truncating.

  Found on device (#434). Worth noting what it was *not*: `.caption` already
  scales with Dynamic Type, so this was never a scaling bug — the size was
  simply wrong, and the surrounding work is what made it noticeable.

## 0.29.04 “Clarity” — 2026-09-28

### Added
- **State no longer depends on colour alone** (#436). Audited every place a
  conditional colour carried meaning. Most were already sound — the download
  states each have their own glyph (checkmark, exclamation, stop), and error
  text is words, with the colour only reinforcing them. Two were not:

  - **Shuffle and repeat** signalled "on" by turning the accent colour and
    nothing else: same glyph, same size, same position. Someone who cannot
    separate the accent from the inactive grey could not tell whether shuffle
    was running. Each now carries a dot beneath it when active — the
    convention Apple Music and Spotify both use — which is a shape appearing
    rather than a colour changing, and grows slightly when the system's
    Differentiate Without Colour setting is on.
  - **The artist page's track rows** marked the playing track by accent
    colour only, while every other track list in the app draws the equalizer
    over the artwork. It now uses the same component as the rest.

## 0.29.03 “Clarity” — 2026-09-28

### Fixed
- **An accent set to black produced unreadable text** (#437). The guardrail
  that keeps a chosen accent legible walks the colour lighter until it clears
  a contrast ratio, but it walked by *multiplying* each channel — and 0 × 1.08
  is still 0, so black never moved. It also gave up after 20 steps, where
  black needs 38. The loop ended at #1C1C1C on a near-black background,
  handed that back as text, and nobody could read it.

  Lightening now adds a point as well as multiplying, the step limit is 60,
  and if a colour still cannot be walked to the target it falls back to plain
  white or black. Verified by sweeping the colour cube — 16,384 combinations
  across both backgrounds and both thresholds — with no failures.

### Added
- **Accent text meets WCAG AA** (#437). Measured rather than judged: the
  default accent scores **4.23:1** on the default dark background, under the
  4.5:1 needed for body text, and the accent is fully user-configurable so
  another choice can be far worse. `readableAccent(on:)` holds text to 4.5:1;
  the existing `legibleAccent(on:)` stays at 3:1, which is the right floor for
  large text and for shapes. Applied to the two places the accent carried
  words: the artist link on the player and the "Recently added" eyebrow.

- **Reduce Transparency** gives the now-playing bar a solid fill instead of a
  blur. A blur behind text is the one place translucency costs legibility.

### Measured, and fine
The rest of the ink ramp passes on both themes — the dimmest text colour in
use scores 5.28:1 at worst, above the 4.5:1 bar. `ink600` sits at 3.4:1 but
is only ever a placeholder glyph and a tint, never text. This had been
recorded as *suspected failing*; the arithmetic says otherwise.

## 0.29.02 “Clarity” — 2026-09-28

### Added
- **Reduced Motion is honoured across the app** (#435). It was respected in
  exactly one place — the playing equalizer — and ignored everywhere else.

  - **The scrolling now-playing title holds still.** This was the app's one
    piece of continuous, unprompted movement: a long title slides back and
    forth for as long as the record plays. It truncates instead — less of the
    title, but a screen that is not moving while someone reads it.
  - **Lyrics still follow the song**, because losing your place would be
    worse, but the line arrives instead of travelling.
  - **Reader page turns and the chrome toggle** arrive rather than slide.
    Someone who sets Reduced Motion may be turning pages for an hour.
  - **Filter chips** change without the transition. The theme's curve is a
    static constant and cannot read the environment, so the choice is made in
    the view that draws them.

  Cross-fades are left alone: an opacity change is not motion, and replacing
  it with a hard cut makes the interface worse for no benefit.

## 0.29.01 “Clarity” — 2026-09-28

### Added
- **Text scales with the reader's chosen size** (#434). The app was written
  with literal point sizes — `.font(.system(size: 15))` — in 25 files. A
  literal size ignores Dynamic Type completely, so the app looked identical at
  the largest accessibility setting and the smallest. That is the single most
  common reason someone cannot read an app at all.

  35 text sites now scale. Icon glyphs, the reader's own size control and
  sizes derived from geometry stay fixed, because a symbol is a drawing and
  scaling it does not help anyone read.

  The obvious fix does not exist: there is no `Font.system(size:relativeTo:)`.
  Only `Font.custom` takes a `relativeTo:`, and that needs a named face rather
  than the system font. `ScaledFont` scales the size through `UIFontMetrics` —
  what the text styles use underneath — and hands it to the ordinary system
  font, so it tracks Dynamic Type exactly while keeping the design's sizes.

- **Layouts that would break at the accessibility sizes now change shape.**
  - Film and show facts stack label above value instead of holding a 120pt
    label column. At AX5 that column left almost nothing for the value.
  - Titles in scrolling lists wrap to three lines instead of truncating to
    one. At AX5 a row holds roughly eight characters, so every row in a list
    read "Symphony No…" and the list stopped distinguishing its contents.
    Fixed-size tiles still truncate, since they cannot grow.
  - The scrolling marquee title reserved a fixed line height, which would
    have clipped the now-playing title as soon as the font grew.

### Known gaps
- **Not yet checked on a device** at the accessibility sizes. The
  Accessibility Inspector's Dynamic Type slider at AX5 is the real test and
  has not been run; expect more layout work after it.

## 0.29.0 “Clarity” — 2026-09-28

### Added
- **VoiceOver across the app** (#433). Labels existed in one file out of
  eighty. Everywhere else the screen reader announced SF Symbol names, so the
  transport bar read as "backward fill, play fill, forward fill" and the
  account button was an unnamed circle. 30 of 84 files now carry accessibility
  modifiers.

  What changed, beyond naming buttons:

  - **Rows are read as sentences.** A search result, a download, an episode
    and a cast member were each several loose fragments — artwork, then a
    title, then a subtitle, none of them saying it was a button. Each is now
    one element that says what it is.
  - **State that was only a colour is now spoken.** A dimmed search row means
    "cannot play offline"; a green tick means "downloaded"; a faded download
    row means "expired". All silent to a screen reader, and all invisible to
    anyone who cannot distinguish the colours. Each is said aloud, which is
    the Differentiate Without Colour work as much as the VoiceOver work.
  - **The scrubber was unusable.** VoiceOver read the raw bound — "847" — and
    offered no way to move it. It now speaks position and duration and takes
    an adjustable action in fifteen-second steps.
  - **Durations are spelled out for speech.** "3:07" is read as a clock time,
    not a length, so spoken values say "3 minutes 7 seconds".
  - **Countdowns too.** The download chip is written narrow — "3d" — which was
    read as "three d". Aloud it is "Expires in 3 days".
  - **Repeat has three states shown by one glyph and a colour**, so off and
    all were indistinguishable. It announces which is active.
  - **Send-for-review options are radio buttons** and carry the selected
    trait rather than signalling the choice with a filled circle.
  - **Subtitles announce their state** — on/off differed only by a filled
    glyph. This is the control for a feature we declare as supported.
  - **Decorative artwork placeholders are hidden** rather than announced;
    they repeat what the row's label already says.

  Voice Control benefits from the same labels, since it speaks them too.

### Known gaps
- **Not yet verified on a device with the screen curtain on**, which is the
  only thing that proves any of this. Tracked on #433.
- **Larger Text is not done** (#434): 25 files still use fixed point sizes
  that ignore the reader's chosen text size.
- **Contrast is unmeasured** (#437). The dimmer end of the ink ramp is
  suspected to fall below WCAG AA for secondary text.
- **Audio descriptions are unsupported** (#443) and are not declared.

## 0.28.1 “Cascade” — 2026-09-26

### Fixed
- **Every download was filed under "Unknown Artist / Unknown Album"**
  (S-417). 0.28.0 moved downloads into the Files-visible library using the
  sidecar beside each file — and that sidecar recorded a title, a subtitle
  and a duration, but never an artist or an album. So the layout had nothing
  to work with and put the whole library on one shelf.

  Sidecars now carry the artist, album, track number, author, year, season and
  episode. Captured when the download starts, while the catalogue entry is in
  hand, because a download also has to be filed correctly offline — when
  there is nowhere else to look them up.

  **Files already misfiled are moved again**, once, on the next launch. Their
  sidecars are backfilled from the catalogue first, since the files needing
  repair are exactly the ones whose sidecars never knew where they belonged.
  A track that genuinely has no artist stays where it is rather than being
  shuffled between identical paths, and a repaired file is not picked up
  again.

  Empty "Unknown Artist" folders left behind by the repair are removed.

## 0.28.0 “Cascade” — 2026-09-26

### Added
- **Downloads are visible in the Files app** (S-416), under
  `SoundChex/Media`, laid out exactly as the desktop library:

      Music/Artist/Album/## Track.mp3
      Movies/Title (Year)/Title (Year).mp4
      TV/Show/Season 01/Show - S01E02.mkv
      Books/Author/Title.epub

  Before this they sat in a hidden cache as `42.media` — named by database
  id, invisible, and impossible to do anything else with. They are the
  person's own media and should be reachable like any other folder.

  **Existing downloads are moved, not copied.** Nobody should need twice the
  space to gain a folder they can browse, and two copies of a library drifting
  apart is its own bug. Anything that cannot be moved is left where it is and
  keeps playing.

  The folder stays excluded from iCloud backup, as the old cache was: pushing
  a few hundred albums into someone's iCloud allowance is not what downloading
  them meant.

- **Books can be downloaded.** They had no download control anywhere in the
  app — not on a row, not in the reader — so a book could not be read without
  the server. There is now one beside Read. It does not ask how long to keep
  it: a book is a few megabytes, and that prompt exists for films.

### Changed
- Deleting a download now removes the empty Artist and Album folders it
  leaves behind. A library of empty folders in Files is worse than one that is
  simply missing things.

### Known gaps
- A file in Documents belongs to the person, so it can be renamed or deleted
  from Files. Playback treats a file that has gone as not-downloaded and
  offers it again, rather than failing at the moment of playing — but the app
  cannot tell a deliberate deletion from an accident.
- Nothing writes artwork or metadata sidecars beside the media yet, so another
  player reading the folder sees whatever the file's own tags say.

## 0.27.1 “Reverie” — 2026-09-26

### Fixed
- **A downloaded track would not play when the server was unreachable**
  (S-415). `play()` refused outright if the session had no API client, logged
  "Playback ignored", and stopped — even though the bytes were already on the
  device and no server was needed. Only the *streaming* branch ever needed a
  client, and now only it requires one. A book still resumes where it was left
  when the server can be asked, and starts from the beginning when it cannot,
  rather than refusing to play.

- **"Offline" meant the wrong thing** (S-415). It asked whether a network
  interface existed, which for this app is nearly the wrong question: you run
  the server yourself, usually at home or on a tailnet, so a phone on mobile
  data or someone else's wifi has a fine internet connection and no route to
  the library whatsoever.

  The old code admitted this in its own comment — "a phone on hotel wifi with
  no route to a home tailnet reads as online here" — and treated it as an edge
  case. It is the normal case away from home: nothing greyed out, every
  undownloaded row accepted a tap, and every one of those taps failed.

  Offline now means the server did not answer. The interface is only the
  trigger to go and ask: no interface is a definite no, and an interface that
  appears or changes prompts a fresh probe, as does the app coming forward and
  a request that fails — that last one being the most truthful signal
  available, since it is the real thing failing rather than a test.

  Before a server is configured the app stays optimistic, so signing in does
  not happen behind a greyed-out library.

## 0.27.0 “Reverie” — 2026-09-25

### Added
- **Films and shows say what they are** (S-412). The detail page had artwork, a
  play button and a list of episodes. Everything that helps someone decide what
  to watch was in the database, unsent; now it is both sent and shown.

  - **Cast and crew**, as rails of faces with the character each played. A cast
    is scanned for someone you recognise, not read top to bottom. Billing order
    is the server's, so the lead comes first.
  - **The facts**: year, runtime, rating, director or creator, studio or
    network, seasons and episodes, IMDb and Rotten Tomatoes scores, language
    and country.
  - **The tagline**, set in italics above the rest — it is the film talking
    about itself rather than a fact about it.

  Credits are fetched when the page opens rather than carried in the library
  sync. Every device mirrors the whole catalogue, and 8,323 items carry
  credits; downloading every actor of every film so one screen can show a
  handful is not a trade worth making.

  Every row is conditional. An item that was never enriched shows a short page
  rather than a column of blank labels.

### Known gaps
- **Still no description.** There is no overview or synopsis column anywhere in
  the database — `tagline` is a marketing line, not a plot. TMDB returns one
  and the pipeline discards it, so this needs a migration and an enrichment
  change before any client can show it.
- Tapping a cast member does nothing yet. There is no person page.

## 0.26.0 “Resonance” — 2026-09-25

### Added
- **The home page reacts to what you play** (S-414). It used to show
  "Recently added" and one row per media type — the same rows on day one and
  day five hundred, reflecting nothing you had ever done.

  - **Continue watching** and **Keep reading** at the top, because something
    you started is the least speculative thing the page can offer: you already
    chose it. Fetched from the server, which is the only place resume position
    lives — the library mirror does not carry it, so the device could not work
    this out from what it holds.
  - **Recently played**, from the play dates already in the mirror and unused
    by this page until now.
  - **A hero that changes.** It was always the newest item with artwork, which
    is why it never moved: a library that has stopped growing had a permanent
    hero. It now prefers something you have played — and deliberately not the
    *most* recent, which is probably still playing and already visible in the
    now-playing bar.

  A library with no history still gets a hero and a page: the old rows remain
  underneath, and each new row appears only when it has something to show. A
  single played item does not earn a row of its own.

  The continue shelves refresh on every visit to the page, because they are
  exactly the rows that go stale — you watched something, came back, and it
  should have moved.

### Known gaps
- Rows are recency, not taste. Nothing ranks by how much you liked something,
  because nothing measures that yet (S-289).
- If the continue request fails the shelves are left as they were and nothing
  is said. A home page with one row fewer is better than one with an error
  where a row should be.

## 0.25.0 “Motif” — 2026-09-25

### Added
- **Suggestions under Your Library** (S-413). The page said what you had just
  played; it now also says what to play next.

  Three shelves, built from what the device already holds — the mirrored
  catalogue's play dates and the recent-contexts store — rather than waiting
  for a recommender to exist:

  - **More from ARTIST**, for whoever you played last. The least speculative
    suggestion available: you chose them minutes ago. Excludes the album you
    are actually listening to, so it is *more* rather than the same thing.
  - **You haven't heard this in a while** — albums you played once and have
    not returned to, oldest first. Deliberately *not* "never played": that is
    the rest of the library, and suggesting it is just browsing.
  - **On repeat** — recently played albums, reaching further back than the
    handful of contexts above it.

  Every shelf is honest about its own emptiness. A library with no history
  produces fewer shelves rather than empty ones, and a shelf with a single
  item is dropped rather than given a header over nothing. An album counts as
  recently played if *any* of its tracks is.

  When the real recommender lands (S-289) these become the fallback, or the
  shape the server fills.

### Known gaps
- The shelves are recency, not taste. Nothing ranks by how much you liked
  something, because nothing measures that yet.
- Music only. Movies, shows and books have no equivalent — continue watching
  needs a server endpoint that does not exist (S-414).

## 0.24.0 “Vamp” — 2026-09-25

### Added
- **The artist and album on the now-playing page are tappable** (S-412). They
  were plain text, which made "what else is on this?" a trip back through
  three screens. Both now open the real page, pushed inside the player rather
  than dismissing it — tapping an artist should not stop the music or throw
  away the screen you were on.

  A track whose artist or album is not in the library — a single, or one
  mid-scan — stays plain text rather than offering a link to an empty page.
  Resolution uses the same grouping keys the browse pages use, so you land on
  exactly the page the library shows rather than a near-match.

  The album line is new here; the context line above the artwork named it, but
  a label is not somewhere to go.

### Fixed
- **A car over Bluetooth showed no album name** (S-413). The now-playing info
  carried title, artist, duration and artwork, but never
  `MPMediaItemPropertyAlbumTitle` — which is the key head units actually read.
  With it unset they show nothing, which reads as missing metadata rather than
  as an app that did not send it.

  Album artist, track number and release date go with it: the app already had
  all three and some head units display them. Absent values are sent as nil
  rather than an empty string, so a unit can collapse the row instead of
  faithfully displaying a blank line.

  This affects the lock screen and CarPlay too, not only Bluetooth.

## 0.23.4 “Segue” — 2026-09-25

### Fixed
- **The app could not be uploaded at all.** App Store Connect rejects an iPad
  build whose `Info.plist` names only portrait: all four orientations must be
  declared to support iPad multitasking. This had been a build warning for a
  while; at upload it is a hard rejection.

  All four are now declared — but declaring an orientation is not the same as
  being ready for it, and these layouts have no landscape handling yet. So the
  plist says what the app is *allowed* to do and `OrientationLock` says what it
  *currently* does: portrait everywhere, except the video player, where
  landscape is the point and a full-screen AVPlayer already handles rotation
  itself.

  As each screen learns landscape it opts in and the lock shrinks. Rotating
  the whole app into unprepared layouts would have shown testers something
  visibly broken, which is a worse answer to a validator complaint than a
  temporary lock.

## 0.23.3 “Segue” — 2026-09-25

### Fixed
- **Xcode Cloud builds could not start at all.** `SoundChex.xcodeproj` is
  gitignored — `project.yml` is the source of truth and XcodeGen writes the
  project from it — so a clean cloud checkout had nothing to build. The
  failure looked like a broken configuration rather than a missing file.

  `ci_scripts/ci_post_clone.sh` now installs XcodeGen and generates the
  project after the clone. Apple fixes that path and filename, and the file
  must be executable or it is skipped in silence, which looks exactly like it
  not being there.

- **The scheme was not shared**, which would have been the next failure and
  would have looked identical. XcodeGen generates an implicit scheme that
  `xcodebuild` can find, but Xcode Cloud's workflow editor lists only schemes
  written to `xcshareddata` — with none there, a workflow has nothing to
  select. The scheme is now declared explicitly in `project.yml`, with Release
  for archive and profile.

  Verified by cloning the repository afresh, running the script, and archiving
  in Release: the archive carries the right version, the privacy manifest and
  the encryption declaration.

## 0.23.2 “Segue” — 2026-09-25

### Added
- **The pieces an App Store upload requires.** Nothing user-facing; the app was
  not uploadable without them.

  `PrivacyInfo.xcprivacy`, required by Apple since May 2024 — an upload
  without one is rejected outright. It declares that the app collects nothing,
  which is true: there is no SoundChex-operated backend to collect into. It
  also declares the two "required reason" APIs actually called, UserDefaults
  and free-disk-space, both for their own obvious purposes.

  `ITSAppUsesNonExemptEncryption: false`. Without it every upload stops with a
  Missing Compliance prompt before any tester can install the build. The app
  uses only the system's HTTPS, which is exempt.

  `Plans/TestFlight.md` documents the rest — the Apple-side setup that cannot
  live in a repository, and draft App Review notes explaining why the app
  allows plain-HTTP connections (users' own servers on private addresses
  cannot hold public TLS certificates).

### Known gaps
- No demo account exists for App Review. Internal TestFlight testing does not
  need one; external testing will fail without it, because a reviewer who
  cannot sign in cannot see the app work.

## 0.23.1 “Segue” — 2026-09-25

### Added
- **A warning before a download expires** (S-405). A timed video download now
  says so before it goes: a day's notice on a week or three days, four hours
  on a 24-hour download. Tapping opens Downloads, where everything expiring is
  in one list.

  **Local notifications, not a background task.** iOS delivers a scheduled
  local notification at the time you asked for whether or not the app is
  running, and needs no entitlement to do it. What iOS does *not* promise is
  background execution, so the file is still deleted by the sweep when the app
  next opens — and the notification says the download *will be* removed rather
  than that it was, because on that device it is still there.

  The warning is cancelled when the download is watched, removed or has
  already gone, and rescheduled when watching pushes the deadline back. An
  alert about something that is no longer going anywhere is how people learn
  to ignore alerts.

  Permission is asked the first time someone picks a timed download, not at
  launch. A prompt before the app has shown what it is for is the one people
  deny, and a denial cannot be asked again.

  Warnings are cleared on sign-out, along with the rest of the account's
  history.

### Known gaps
- A short window can still pass without a warning: nothing is scheduled when
  under a minute would remain, since a warning arriving as you look at the
  screen you started from is noise.
- Notifications are iOS-only so far. Android and desktop come with those
  platforms.
- There is no in-app list of what is about to expire, beyond the countdown on
  each row in Downloads.

## 0.23.0 “Segue” — 2026-09-25

### Added
- **Video downloads ask how long to keep the file** (S-404). Downloading a
  film or an episode offers 24 hours, 3 days, a week, or keep it. A film is
  2–10GB against a song's 5MB, so an unattended video download is the one
  that quietly fills a phone.

  Music and books are unaffected and still download permanently — asking the
  same question about a 5MB song would be a tax on every tap for no benefit.

  **Watching resets the clock.** The window means "unused for this long", not
  "this long since you tapped download", so a series you are part-way through
  does not vanish between two episodes. A 24-hour download stays a 24-hour
  download when extended; it does not quietly become a weekly one.

  **When the time is up the file goes but the row stays**, marked expired,
  with a tap to download it again on the same terms. A film that vanished
  without trace would be indistinguishable from one you never downloaded.

  Downloads shows the time left on each timed item — "3d", "4h", "22m".

  The sweep runs on launch and when the app comes forward, not on a background
  timer: iOS would not honour one reliably, and a file deleted while nobody is
  looking is a file nobody was told about.

- **Episodes can be downloaded, from a long press** (S-388). The show page had
  no download control at all, so downloading a series meant playing each
  episode and hoping. Long-press an episode for Download or Remove; stored
  episodes show a green marker on the row.

  There is deliberately **no season or series download-all**. An episode is
  gigabytes, and a "download this season" button turns filling a phone into a
  one-tap mistake — the control exists for anyone who wants it, without
  inviting a 40GB tap. Films, which have no episode rows to hang a menu off,
  get a download button beside Play.

### Known gaps
- The expiry sweep runs when the app opens, so a file can outlive its window
  by however long the app stays closed. It is deleted the moment you come
  back, which is also the first moment you could have been told.
- Nothing warns you before an expiry. The row simply reads "expired" next time
  you look.
- Retention is per download, not a setting — there is no "always keep video
  for 3 days" default yet.

## 0.22.0 “Coda” — 2026-09-25

### Added
- **Send for review** (S-400). A "Send for review" entry in the track kebab,
  on every list that shows one — songs, album tracks, an artist's tracks, the
  now-playing page and search.

  It asks twice, on purpose. Reporting an item hides it from the library until
  someone has looked at it, which is a large consequence for one tap in a menu
  whose neighbours are "Play next" and "Add to queue". So tapping it raises a
  confirmation that says exactly what will happen — hidden until reviewed,
  nothing deleted, it comes back — and only a deliberate "Send for review"
  opens the sheet that asks why.

  Five reasons: wrong metadata, file problem, wrong cover, duplicate, something
  else. Each carries a line saying what it covers, and there is an optional
  note. The report lands on the review screen in the server's admin panel,
  with the reason and the note attached.

### Changed
- **README rewritten against the code.** It described a three-feature app:
  `Sources/Features` was listed as `Auth`, `Browse`, `Playback` when there are
  ten directories, and the API section named six endpoints while the app calls
  twenty. Downloads, playlists, lyrics, AirPlay, the reader, video, the admin
  area and "Your Library" were all shipped and unmentioned.

  It also pointed contributors at `Plans/Issues.md` for "the issue list", and
  that file's entire content is a note saying the issues moved to the admin
  tracker.

  Added: what the app actually does, the iOS 17 deployment target (stated
  nowhere before), the command-line device build, the `xcodegen generate`
  trap, and the fact that there is no test target — so nobody goes hunting for
  a suite that does not exist.

- **A stale comment in `project.yml`** described 0.4.0 "Interlude" directly
  above `MARKETING_VERSION: "0.21.0"` — seventeen minors out of date. It now
  says where release names actually live, which is `AppRelease.swift`: a name
  written only in the CHANGELOG is not shipped.

### Known gaps
- Nothing tells you what came of a report. Once sent, the item simply stops
  appearing until an admin clears it.
- The row does not disappear until the next library sync, so a reported track
  can still be tapped for a few seconds — it will refuse to play, because the
  server has already hidden it.
- Album and artist pages report per track; there is no "report this whole
  album" yet.

## 0.21.0 “Reprise” — 2026-09-25

### Added
- **Your Library on the Music page** (S-392). With no filter chip selected,
  the page used to list Albums and then Artists — which is exactly what the
  chips above already do, so the landing was a worse copy of the next tap. It
  now shows what you last played, newest first.

  The unit is the *context* you played from, not the track. Put on an artist
  and the artist appears; tap a track inside an album and the album appears;
  play a playlist and the playlist appears. A song appears on its own only
  when a song is genuinely what you picked — out of the Songs list, or off
  this page.

  This is remembered on the device. The server cannot answer it: `media_plays`
  has a `source` column, but it holds a surface name ("browse", "home") rather
  than an identity, and the only playback ping the client sends is
  `POST /items/{id}/progress`, which carries position and duration and nothing
  about where the track came from.

  Entries de-duplicate by identity, so playing one album four times in an
  evening leaves one entry at the top rather than four. History is cleared on
  sign-out and on a server change, alongside the cached library — one
  account's listening should not greet the next one.

  Until there is any history — a fresh install, or just after a sign-out —
  the page falls back to the old browse shelves. An empty page on first launch
  would be worse than a redundant one.

### Fixed
- **Batch download progress now persists and counts down** (S-394). The artist
  and album pages announced "Downloading 40 songs…" and cleared the line
  after three seconds. Fetching a discography takes minutes, so for the rest
  of them the page looked idle and the only way to check was to leave and come
  back. The line now stays up and counts — "Downloading 12 of 40" — then
  reports what landed.

- **A failed track no longer strands the playlist download at "1 remaining"**
  (S-394). The playlist page had its own copy of this logic, and it counted
  only tracks that reached `stored`. A batch containing a dead file therefore
  never reached zero, so the completion message never fired. Failures now
  count as settled, and the final line says what actually happened:
  "Downloaded 39 of 40 — 1 failed" rather than claiming success.

  All three pages now share one `BatchDownloadStatus`, so there is one place
  for this to be right instead of three chances to get it wrong.

### Known gaps
- Recent contexts are per-device, not synced between devices. Playing an album
  on the Mac will not put it on the phone's landing page.
- A context whose album or playlist has since left the library is skipped
  rather than shown as unavailable.

## 0.20.0 “Tempo” — 2026-09-25

### Added
- **Albums and Songs tabs on the artist page** (S-391), with sorting for each.
  Songs: A–Z, Z–A, album, release date, recently played. Albums: A–Z, Z–A,
  release date, recently played.

  The sort control sits beside the tabs rather than inside each list, so
  switching tabs does not move the control you just used. An album is as
  recent as its most recently played track, and its year is the earliest its
  tracks claim — so a reissued bonus track does not date the whole record to
  this year.

  The Songs tab replaces the old "Popular" list, which showed a fixed top five
  with no way to see the rest.

### Fixed
- **Track rows on the album and artist pages show their download state**
  (S-390), and carry the same kebab the Songs list has — play next, add to
  queue, add to playlist. They had neither, so downloading an album gave no
  per-track feedback at all and a working download looked like a failure.

## 0.19.01 “Cadence” — 2026-09-25

### Added
- **Shuffle and download on the artist page** (S-387). Albums and playlists
  both had a download-all button; the artist page had none, so downloading an
  artist meant opening every album in turn. It is the same pair of controls the
  album page uses, acting on everything by the artist, and it reports the same
  answers — how many started, not enough free space, already downloaded.

  An artist's whole catalogue is a lot to fetch, so saying "not enough free
  space" plainly matters more here than anywhere else.

## 0.19.0 “Cadence” — 2026-09-25

### Added
- **A kebab on the album and artist pages** (S-385): play next, add to queue,
  and add all to playlist — acting on the whole record, or everything by the
  artist, instead of a track at a time from the row kebabs.

  The playlist sheet takes a set now rather than one track, and says how many
  are going in ("Add 11 to playlist") so it cannot be mistaken for adding just
  the one you tapped. Adding a set reports what happened — "Added 11 to Road
  Trip — 3 already there" — rather than asking about each duplicate: the
  "move it to the end?" question is worth asking for one track and not for
  forty.

  Queueing a set inserts it as a block, keeping album order. Inserting one at
  a time would have queued the album backwards.

  Deliberately no "Download all" in the menu: the album page already has a
  download button that reports not-enough-space and nothing-to-do, and a menu
  entry discarding that result would be the same action with worse feedback.

## 0.18.02 “Refrain” — 2026-09-25

### Fixed
- **Loose tracks gather as "Singles" instead of 83 "Unknown album" tiles**
  (S-386). A track with no album fell back to grouping on its *title*, so each
  one became its own album — 83 of them on a real library, every one labelled
  "Unknown album". They are now gathered per artist, which turns 83 tiles into
  33 and says what they actually are.
- **The library refreshes during a long session.** It synced once per launch,
  so a correction made on the server sat unseen until the app was killed and
  reopened. A library screen appearing, or the app returning from the
  background, now re-syncs when the catalogue has gone stale — and does
  nothing when it has not, so moving between tabs still costs nothing.

## 0.18.01 “Refrain” — 2026-09-24

### Added
- **Smart shuffle** (S-289), as a third state of the shuffle button: press it
  to cycle off → shuffle → smart shuffle → off. Smart gets its own glyph
  rather than a badge, since iOS ships one.

  Ordinary shuffle is uniform, which on a library of thousands means mostly
  tracks nobody has chosen. Smart draws two thirds from what this profile
  actually plays — by play count and recency — and a third from everything
  else, interleaved so it does not read as two playlists stuck together.

  The queue is weighted on the server: the phone would need the whole library
  and the whole play history to do it here. If the request fails it drops back
  to ordinary shuffle rather than staying in a mode that quietly means
  nothing.

## 0.18.0 “Refrain” — 2026-09-24

### Added
- **AirPlay** (S-165). An AirPlay button sits between Lyrics and Queue on the
  now-playing page: send the music to a HomePod, an Apple TV, an AirPlay
  speaker, or a pair of AirPods, without leaving the app.

  The audio already *went* to AirPlay — the session is `.playback` with the
  `.longFormAudio` policy, so iOS has always routed it like any music app and
  Control Centre could move it. What was missing was a way to choose the
  destination from inside the app.

  Video was already covered: `AVPlayerViewController` brings its own route
  button.

### Not yet
- **Chromecast** is not in this release. It needs Google's Cast SDK, a
  closed-source binary framework under Google's own licence — a deliberate
  decision against the project's AGPL position, so it waits for one.
- **CarPlay** needs an entitlement from Apple that has not been requested yet.

## 0.17.03 “Bridge” — 2026-09-24

### Changed
- **Versions are written `x.xx.xx`** (S-380). The patch is zero-padded to two
  digits, so a version reads at a fixed width — `0.17.03`, not `0.17.3`. Each
  field is still just a number, so nothing downstream cares. A minor bump
  resets it plainly: `0.18.0`.
- **0.17.x is “Bridge”, not “Encore”.** Encore is reserved in
  `Plans/Versioning.md` for 1.0.0, and 0.17 took it by mistake, skipping the
  planned Bridge. Renamed here and in the three release notes that shipped
  under it; Encore goes back to 1.0.

### Fixed
- **Settings shows the release name again** (S-380). `AppRelease.names` stopped
  at 0.8, so every release from 0.9 to 0.17 displayed a bare number while the
  CHANGELOG called them Coda, Verse, Ledger, Anchor, Folio, Porter and Tether.
  The names only ever existed in the release notes. All of them are in the map
  now, and the plan says to add the entry at the minor bump rather than after.

## 0.17.2 “Bridge” — 2026-09-24

### Changed
- **The scrolling title rests at both ends** (S-379). It revolved without
  stopping, so the title was always moving and never settled long enough to
  read at a glance.

  It now holds at the start, scrolls until the last word reaches the edge,
  holds there, then carries on round. The second rest is at the end of the
  *title*, not the end of the travel — pausing there would just be a blank gap
  sitting still.

  The wrap-around leg runs faster than the reading leg. Nothing is readable
  while the tail goes off and the next copy comes in, and at reading speed
  that stretch was the longest part of the cycle: the title spent most of its
  time off screen.

## 0.17.1 “Bridge” — 2026-09-24

### Changed
- **The scrolling title revolves instead of bouncing** (S-378). It ran to the
  end and eased back, and the turn caught the eye every time — the motion
  became the thing you noticed rather than the title.

  It now travels one way and never turns round: a second copy of the text
  follows the first, and once the first has gone the offset resets. The copies
  are identical, so the reset is invisible and it reads as a revolving door.
  Linear timing too, because a constant speed is what lets it fade into the
  background; the old easing sped up and slowed down every pass.

## 0.17.0 “Bridge” — 2026-09-24

### Added
- **Add to Playlist warns when the song is already there** (S-373). A playlist
  cannot list the same song twice — the pivot's key is the pair — so adding one
  it already holds used to rewrite its position and move it to the end,
  silently. It now asks, and "Move to the end" is offered as the honest
  description of what adding again actually does.
- **Remove from playlist, in the song row kebab** (S-376). Removing a song
  needed a swipe, which is not discoverable. The action appears only on a row
  that is actually in a playlist.
- **Long titles scroll instead of truncating** (S-377). On the now-playing
  page the song title, its subtitle and the "playing from" line marquee when
  they are wider than the space they have — a title cut to "The Road to Hell
  Is Highway 59 (feat…" hides the part that says which track it is.

  Only when it has to: text that fits is left alone, with no animation
  running, because this page is on screen for the length of a record.

### Fixed
- **Add to Playlist adds the song you opened it for** (S-374). The sheet read
  the *live* now-playing track, so if the song changed while the sheet was
  open, it quietly re-targeted and added whatever was playing when you tapped.
  The song is captured when the sheet opens and held.

  Lyrics deliberately keep following the track: the sheet stays open and swaps
  to the new song, which is what you want while a record plays.

## 0.16.2 “Tether” — 2026-09-24

### Fixed
- **A playlist made from "Add to playlist" now shows up** (S-372). Creating one
  from the kebab looked like it had done nothing: the playlist and the track
  were both saved on the server, but the playlists grid loads its list once and
  kept the old copy, so the new playlist stayed invisible until the app was
  relaunched.

  The grid's store is shared through the environment now, the way downloads and
  the theme already were, and the sheet reads and refreshes it — so the sheet
  and the grid can no longer disagree about what playlists exist. Adding to an
  *existing* playlist refreshes it too: the card shows a track count and a
  mosaic of its first few covers, and both just changed.

## 0.16.1 “Tether” — 2026-09-24

### Fixed
- **Playlist covers on the playlists list** (S-371). Every playlist without a
  cover of its own showed a note glyph, while opening it showed the usual 2×2
  mosaic of its tracks' art — so covers appeared only *inside* a playlist. The
  list endpoint carries no tracks, and the card was passing an empty mosaic, so
  there was never anything to draw. The server now sends up to four track
  covers per playlist and the card uses them.

  A server that has not been updated sends no mosaic at all; that decodes to
  empty rather than failing the playlist, so an older server behaves exactly as
  it did before.

## 0.16.0 “Tether” — 2026-09-24

### Added
- **Offline, a track you have not downloaded is dimmed and does not respond**
  (S-362). It said "Not downloaded" only after you tapped it and nothing
  happened; now the row says so before you try. The kebab stays live, because
  removing a download or adding to a playlist are exactly what you reach for
  when a track will not play.
- **The now-playing tell follows the track everywhere** (S-362). The accent
  title and the animated equalizer over the cover were drawn by the library
  list, the album page and the artist page — each separately — and not at all
  in search. One component now, so a song you are listening to looks like it
  wherever you find it.

### Fixed
- **The lock screen keeps up when you scrub** (S-363). Seeking never told the
  system where playback had landed, so the lock screen and Control Centre went
  on counting from the old position and only corrected when pausing and playing
  forced a refresh. They are told on every seek now — and their own scrubber
  works, which it never did: the control was drawn but nothing handled a drag.
- **Queued downloads survive going offline and being closed** (S-364). Only a
  transfer that had already begun was resumed; one still waiting for a slot
  left no resume data and was simply forgotten, so a "download all" interrupted
  early lost most of what it promised. Anything with a sidecar and no file is
  owed, and is picked up when the app reopens or the network returns.

## 0.15.1 — 2026-09-24

### Fixed
- **Downloaded music plays offline** (S-360). Downloads are stored as
  `<id>.media`, and AVFoundation will not open that: given no extension it
  recognises, it answers "Cannot Open" for a file that is a perfectly good MP3
  — verified against the same bytes renamed `.mp3`, which load and report their
  duration. Local playback therefore always failed, and the recovery path fell
  back to streaming, so the only symptom online was that downloads achieved
  nothing. In airplane mode there was nothing to fall back to. The player is
  now handed a hard link named from the file's own container, sniffed from its
  first bytes rather than guessed from the item's type.

### Added
- **Search results carry the same actions as everywhere else** (S-361): play
  next, add to queue, add to playlist, download or remove — behind a kebab at
  the end of each row.

## 0.15.0 “Porter” — 2026-09-24

### Added
- **Import a playlist on the phone** (S-313). Playlists → Import takes an M3U,
  M3U8, CSV or XSPF file — a Spotify export from Exportify works as-is — and
  matches it against your library, showing how many tracks landed. Anything it
  could not place is listed with a search box, so a track can be pointed at the
  right recording rather than silently dropped.

## 0.14.0 “Folio” — 2026-09-23

### Added
- **Kindle-style paginated reading** (S-304). A book is laid out into pages
  that fit the screen and turned by tapping an edge or swiping, instead of one
  long scroll. Page and chapter position carry across a turn, so reading
  progress still means what it did.

## 0.13.1 — 2026-09-23

### Fixed
- **Downloaded covers no longer vanish away from home** (S-329). The server
  builds artwork URLs from the address a request arrived on, and a download's
  sidecar froze whichever one was current when the file was fetched. A cover
  saved at home therefore pointed at the tailnet host, which does not resolve
  anywhere else, and the artwork simply disappeared. Stored URLs are now
  rebased onto the server the device can currently reach. Only this server's
  own artwork paths are touched — a cover hosted by a metadata provider is left
  alone.
- **A cover that failed once no longer stays broken** (S-329). The image loader
  ignored the HTTP status, so a 404's body was cached as though it were the
  image and the cover never recovered even once it became reachable. A
  non-2xx response is now refused and anything cached for it evicted.

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
