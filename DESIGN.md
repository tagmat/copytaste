---
name: CopyTaste
description: A spatial clipboard selector and menu-bar utility for macOS.
colors:
  background: "color(srgb 0.055 0.072 0.085)"
  surface: "color(srgb 0.085 0.105 0.12)"
  raised: "color(srgb 0.13 0.16 0.18)"
  text: "color(srgb 0.94 0.97 0.96)"
  secondary: "color(srgb 0.65 0.72 0.75)"
  mint: "color(srgb 0.74 1 0.53)"
  violet: "color(srgb 0.73 0.65 1)"
  code-number: "color(srgb 0.96 0.81 0.57)"
  code-function: "color(srgb 0.55 0.88 0.9)"
typography:
  heading: {fontFamily: "ui-rounded, system-ui", fontSize: "24pt", fontWeight: 600}
  empty: {fontFamily: "ui-rounded, system-ui", fontSize: "22pt", fontWeight: 500}
  brand: {fontFamily: "ui-rounded, system-ui", fontSize: "20pt", fontWeight: 600}
  link: {fontFamily: "ui-rounded, system-ui", fontSize: "20pt", fontWeight: 500}
  clip: {fontFamily: "ui-rounded, system-ui", fontSize: "18pt", fontWeight: 500}
  search: {fontFamily: "system-ui", fontSize: "17pt", fontWeight: 400}
  section: {fontFamily: "system-ui", fontSize: "15pt", fontWeight: 600}
  file-name: {fontFamily: "system-ui", fontSize: "15pt", fontWeight: 500}
  control: {fontFamily: "system-ui", fontSize: "12pt", fontWeight: 400}
  code: {fontFamily: "ui-monospace, monospace", fontSize: "11pt", fontWeight: 400}
  markdown-heading: {fontFamily: "ui-rounded, system-ui", fontSize: "17pt", fontWeight: 600}
  filter: {fontFamily: "system-ui", fontSize: "11pt", fontWeight: 500}
  metadata: {fontFamily: "system-ui", fontSize: "10pt", fontWeight: 400}
rounded:
  code-block: "7pt"
  thumbnail: "10pt"
  image: "12pt"
  quick-action: "13pt"
  hint-strip: "17pt"
  settings-section: "18pt"
  card: "22pt"
  filter-strip: "24pt"
  search: "25pt"
spacing:
  compact: "6pt"
  small: "10pt"
  standard: "12pt"
  control: "14pt"
  card: "18pt"
  section: "20pt"
  page: "30pt"
  empty: "32pt"
components:
  flight-card: {backgroundColor: "{colors.surface}", textColor: "{colors.text}", rounded: "{rounded.card}", width: "278pt", height: "300pt"}
  search: {textColor: "{colors.text}", typography: "{typography.search}", rounded: "{rounded.search}", padding: "14pt"}
  quick-action: {backgroundColor: "{colors.mint}", textColor: "{colors.background}", rounded: "{rounded.quick-action}", padding: "14pt"}
  settings-section: {backgroundColor: "{colors.surface}", textColor: "{colors.text}", rounded: "{rounded.settings-section}", padding: "20pt"}
---

# CopyTaste — spatial desktop utility

## Overview

CopyTaste by tagmat lives in the menu bar. Its English-language primary surface is a transparent floating selector: a search capsule, pinned clips on the left, a recent-card fan on the right and a compact control strip. A configurable orbit layout combines clips in one fan. Quick settings open in an anchored menu-bar bubble. A regular window is reserved for advanced storage, privacy, collections and retention settings. There is no main history workspace.

RAM remains the default, with optional encrypted local, custom-folder or iCloud Drive storage. The selector and bubble name the actual storage state. First launch requires capture opt-in; sample clips use an isolated session.

## Colors

The frontmatter preserves exact sRGB values. Graphite background, surface and raised tones support soft white text and muted blue-grey metadata. Electric mint marks primary actions, selection, pins and text types; violet distinguishes image/file types and link artwork. Code uses violet keywords, mint strings, muted comments, warm amber numbers and cyan function names on soft white base text. All surfaces use the dark appearance.

## Typography

Use native system and rounded faces. Ordinary clipboard text uses the clip style with 5-point extra line spacing and a seven-line limit; link titles use the link style with a three-line limit. File names stop at two lines; plain file excerpts use 12-point system text and six lines. Code uses 11-point monospaced text with 3-point extra line spacing. Markdown uses rounded semibold headings at 17 points for level one and 14 for other levels, with 11-point body text. Locked headings use rounded 24-point medium text. Quick-action text is 13-point semibold; small captions are 11 points. Counts use monospaced digits.

## Layout

All dimensions are macOS points. The transparent, nonactivating selector is 560 high and at most 1120 wide, constrained to the pointer's screen width minus 40. It is horizontally centered; its lower edge sits 240 below the visible-screen midpoint. Search has a 700-point maximum width and 22-point top inset. The control strip has an 18-point bottom inset.

The default pinned-left/recent-right layout splits when matching pins and unpinned clips both exist outside the Pinned filter. Its pin area is 222 wide, followed by a 14-point gap and the recent fan, within 12-point horizontal insets. The pin stack shows the active pin and up to two others at 0.72 scale, with a count and Show all pins action. Split captions and the Show all pins action use dark surfaces for contrast. Recent cards spread by `max(0, (recentWidth - 350) / 6)` per slot so their shadows can extend without a hard crop. Orbit, pinned-only results and unsplit states use one fan. Each group is newest first. Default selection starts at the newest unpinned match when available. Layout can be changed in quick or advanced settings.

Each fan renders up to seven 278 × 300 card slots. Horizontal spread is `min(196, (availableWidth - 310) / 3.7)` per slot; resting vertical offset is 11 points per distance from centre. Cards use 18-point content insets. Search, type, collection and layout changes reset selection. Navigation wraps through all matches in the bounded history, with a configured maximum of up to 1000 entries; seven is a rendering limit, not a result cap.

The transient menu-bar bubble is 340 wide, with 20-point padding and content-driven height. Advanced settings default to 680 × 720, with a 600 × 600 minimum, a scrollable 30-point page inset, 26-point section gaps and 14-point internal gaps. There is no sidebar or alternate mobile composition.

## Elevation & Depth

Floating controls layer a 94%-opaque graphite surface over native ultra-thin material, with a 0.7-point white outline at 10% opacity. This dark substrate preserves contrast against desktop content. The transparent panel has no native window shadow; individual cards cast black shadows at 40% opacity, radius 22, offset 20 downward. Selected cards use a 1.2-point mint outline at 80% opacity; others use a 0.6-point white outline at 12%.

## Shapes

Cards use continuous rounded corners. Search, filter and hint strips use their distinct corner tokens; short filters use capsules. Circular icon controls are 34 square. The mint brand symbol sits in a rounded square with a 9%-opacity mint backing, corner radius 30% of its size and symbol size 54%. Brand sizes are 34 in search, 36 in the bubble and 42 in advanced settings.

## Components

**Selector motion.** Opening spreads fan cards from compact 18-point slot offsets and a 130-point downward offset. Cards spring with response 0.58, damping 0.76 and a 25 ms stagger per slot distance. Resting cards rotate 3.2° per slot, yaw −8° per slot and scale down by 0.055 per slot distance to a minimum of 0.82. Pointer movement adds up to 3° tilt on each axis. Selection uses a spring with response 0.46 and damping 0.82; search enters with response 0.4 and damping 0.8. The pin area enters from 100 points left with response 0.5 and damping 0.82; stacked pins rotate −5° and offset 7 points right/9 down per layer.

Choosing a fan card flings it 160 points upward while other fan cards drop 95 and spread outward. The departure uses 180 ms ease-in, fading and blurring to 9 points; the chosen card scales to 1.06 and others to 0.68. The controller waits 180 ms before hiding on choice or ordinary dismissal, then copies or pastes when applicable; loss of key status hides immediately. Reduce Motion removes phase/selection animations, tilt, rotation, blur and animated scaling, keeps the static fan positions and compact pin-stack scale, and skips the departure wait.

**Interaction.** Command-Shift-V opens the selector. Arrow keys, mouse wheel and trackpad scrolling navigate. Scroll handling is local to the open selector, follows the dominant axis and ignores momentum; precise scrolling accumulates 28 points per step, with a 90 ms minimum between steps. Return and card activation paste when enabled; Option-Return copies only. Command-P, card pins and filters keep the selector open. Escape dismisses. Direct paste requires Accessibility permission; otherwise feedback and its permission action appear in the menu-bar bubble. Context menus provide copy, paste, pin, collection and delete. Icon actions have accessible names; selected cards expose a summary and selected state.

**Previews.** Real image representations take precedence over accompanying URLs. Image thumbnails stay in memory and crop to a 174-point preview. Files use a 126-point image or first-page PDF preview, a text preview, or a native 70 × 84 type icon with name and size. Eligible text files up to 512 KB decode at most 8000 bytes, then choose Markdown, code or plain text by format; filenames participate in search. Links show a title and host without fetching pages.

Markdown and code previews use local SwiftUI text and AttributedString formatting. Markdown parsing is bounded to 8000 characters and 120 input lines; cards show at most six blocks, with headings, inline emphasis, lists, quotes, rules and fenced code. Text-card Markdown clips at 190 points. Links are inert and images are never fetched. Code highlighting is bounded to 8000 characters, with ten lines in text cards, seven in files and five inside Markdown fences. Fenced code has 8-point padding, code-block corners and an 18%-black backing.

**States.** Empty and no-match results replace cards with a frosted message and capture opt-in when applicable. Locked history replaces previews with authentication and, for iCloud, a secure passphrase field. The bubble shows capture/lock state, clip count, storage, native mini switches and conditional permission guidance. Advanced settings use native fields, pickers and alerts within graphite sections. Errors and feedback omit clipboard payloads.

## Do's and Don'ts

- **Do** keep the selector transparent around its independently surfaced controls and cards.
- **Do** preserve readable search, keyboard focus and explicit copy-only access.
- **Do** keep storage, capture, permission and sample states truthful.
- **Don't** introduce a persistent main/history window, rail or document workspace.
- **Don't** apply flight, tilt or scaling when Reduce Motion is enabled.
- **Don't** replace real image/file previews with accompanying URL text or expose private content in diagnostics.
