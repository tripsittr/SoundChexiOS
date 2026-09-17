# Design Spec — matching the web media center

The app matches the web media center's **style and theme** (not a pixel clone).
Dark, cinematic streaming UI; artwork is the content, chrome stays out of the
way. Font: system (web uses Figtree; system sans is close enough for now).

## Palette (exact, from tokens.css)

| Token | Hex | Use |
|---|---|---|
| base-900 | #08080B | app background |
| base-800 | #0F0F14 | cards, nav fill, popovers |
| base-700 | #16161D | artwork placeholders, hover fills |
| base-600 | #1F1F28 | borders, dividers, seek track |
| base-500 | #2A2A35 | subtle borders |
| ink-100 | #F4F4F5 | primary text |
| ink-300 | #B8B8C0 | secondary text |
| ink-500 | #8A8A96 | muted text, inactive tabs |
| accent | #E11D3A | buttons, active markers, progress |
| accent-hot | #FF2A4A | hover/pressed |
| stored green | #34D399 · error pink | #FCA5A5 · amber | #FBBF24 |

Interpolated ink used in markup: ink-200 #D6D6DC, ink-400 #A1A1AC, ink-600 #6B6B78.
Ease curve: cubic-bezier(0.16, 1, 0.3, 1). All in `SoundChexTheme`.

## Shapes
Poster/art radius 8px; large art 12px; buttons 6px; pills 999px.
Aspect: movies/books/shows 2:3, music/albums/artists 1:1, backdrop 16:9.

## Home = hero + horizontal rails (Netflix-style)
- Hero at top (eyebrow "Recently added"), rails pulled up over its bottom fade.
- Hero: blurred full-bleed backdrop (scale 1.1, brightness 0.45, saturate 1.5),
  bottom + left gradient scrims, bottom-aligned content. Foreground sharp poster
  (≥tablet). Eyebrow: accent, uppercase, 0.2em tracking, 12px bold. Title:
  extrabold 30→48→60px with text shadow. Primary "View details" button
  (bg ink-100, text base-900), secondary "Browse …" (white/15 backdrop-blur).
- Rail: heading 16→18px bold; "View all →" ink-500. Track scrolls horizontally,
  poster width 144px (phone) / 176px (≥tablet), gap 12/16px, snap start.

## Poster tile
Art box, aspect per type, radius 8px, bg base-700. Title overlay with `.scrim`
gradient (to top: base-900 0.95 → 0.6 @35% → transparent @75%). Title 14px
semibold ink-100 (2 lines); subtitle 12px ink-300 "subtitle • year" (1 line).

## Song row
li flex gap-12px py-8px rounded-8px, hover bg base-800/60. Play/art 44px square
radius 4px bg base-700 (number → play triangle on hover). Title 14px ink-100,
subtitle 12px ink-500. Duration (≥tablet) 44px right, 12px tabular ink-500.
Download button hidden on the standalone offline shell.

## Now-playing bar
Fixed bottom, above the tab bar. Bg base-800 @95% + blur-12. Top border
base-600/60. Seek: 1px track bg base-600, played fill accent. Art 44→48px radius
4px. Title 14px medium ink-100, subtitle 12px ink-500. Transport: prev/next 20px
ink-300; play/pause round bg ink-100 icon base-900. Tap → full-screen sheet
(big 384px art radius 12px, 64px round accent play).

## Bottom tabs
Bg base-800 @94% + blur-12, top border base-600. Tab: icon 22px, label 10px
weight 500. Active ink-100 + accent top-bar (28×2px), inactive ink-500.

## Detail screens (album/artist)
Header: big artwork (album 1:1 176→208px; artist circle 112→144px), eyebrow
uppercase ink-500, title 24→36px bold, meta line "·"-joined ink-500. Action row:
Play pill (bg accent, white, radius 999px), Shuffle + Download 44px bordered
circles. Track list `<ol>` divided by base-700/60, rows py-10px.

Full detail (all sizes, gradients, badges) is in the subagent extraction that
produced this file; this is the working summary. When in doubt, open the web
Blade component of the same name.
