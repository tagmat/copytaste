---
name: CopyTaste
description: A native Mac clipboard library with warm paper surfaces and a clear memory boundary.
colors:
  rail: "#243D34"
  rail-secondary: "#C7D3C9"
  canvas: "#F7F6F0"
  paper: "#FEFDF9"
  ink: "#242D28"
  secondary: "#626A61"
  accent: "#A6442F"
  selection: "#E5EBDD"
  divider: "#E0E2D8"
  white: "#FFFFFF"
  brand-gold: "color(srgb 0.88 0.76 0.51)"
  rail-selected: "rgba(255, 255, 255, 0.13)"
  rail-card: "rgba(255, 255, 255, 0.065)"
typography:
  display: {fontFamily: "ui-serif, serif", fontSize: "44pt", fontWeight: 500, letterSpacing: "-1pt"}
  locked-title: {fontFamily: "ui-serif, serif", fontSize: "30pt", fontWeight: 500}
  section-title: {fontFamily: "ui-serif, serif", fontSize: "28pt", fontWeight: 500}
  preview: {fontFamily: "ui-serif, serif", fontSize: "25pt", fontWeight: 400}
  page-title: {fontFamily: "system-ui, sans-serif", fontSize: "24pt", fontWeight: 600, letterSpacing: "-0.5pt"}
  empty-title: {fontFamily: "ui-serif, serif", fontSize: "22pt", fontWeight: 400}
  brand: {fontFamily: "ui-rounded, system-ui, sans-serif", fontSize: "20pt", fontWeight: 600}
  picker-search: {fontFamily: "system-ui, sans-serif", fontSize: "18pt", fontWeight: 400}
  settings-label: {fontFamily: "system-ui, sans-serif", fontSize: "15pt", fontWeight: 600}
  body: {fontFamily: "system-ui, sans-serif", fontSize: "14pt", fontWeight: 400}
  code: {fontFamily: "ui-monospace, monospace", fontSize: "14pt", fontWeight: 400}
  clip-title: {fontFamily: "system-ui, sans-serif", fontSize: "13pt", fontWeight: 600}
  label: {fontFamily: "system-ui, sans-serif", fontSize: "12pt", fontWeight: 400}
  caption: {fontFamily: "system-ui, sans-serif", fontSize: "11pt", fontWeight: 400}
  metadata: {fontFamily: "system-ui, sans-serif", fontSize: "10pt", fontWeight: 400}
  micro: {fontFamily: "system-ui, sans-serif", fontSize: "9pt", fontWeight: 400}
rounded:
  thumbnail: "4pt"
  control: "8pt"
  picker-row: "9pt"
  clip-row: "10pt"
  preview: "12pt"
  panel: "18pt"
spacing:
  compact: "4pt"
  small: "8pt"
  inset: "10pt"
  standard: "12pt"
  row-inset: "14pt"
  medium: "16pt"
  loose: "18pt"
  section-inset: "20pt"
  list-inset: "22pt"
  section: "24pt"
  detail-gap: "28pt"
  detail-inset: "30pt"
  page-inset: "32pt"
  welcome-inset: "40pt"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.white}"
  navigation-selected:
    backgroundColor: "{colors.rail-selected}"
    textColor: "{colors.white}"
    rounded: "{rounded.control}"
    padding: "10pt 12pt"
  search:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "10pt"
    width: "240pt"
  clip:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.clip-row}"
    padding: "14pt"
  clip-selected:
    backgroundColor: "{colors.selection}"
    textColor: "{colors.ink}"
    rounded: "{rounded.clip-row}"
    padding: "14pt"
  storage-card:
    backgroundColor: "{colors.rail-card}"
    textColor: "{colors.white}"
    rounded: "{rounded.clip-row}"
    padding: "14pt"
  picker:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    width: "650pt"
    height: "460pt"
  picker-row-selected:
    backgroundColor: "{colors.selection}"
    textColor: "{colors.ink}"
    rounded: "{rounded.picker-row}"
    padding: "13pt 14pt"
---

# Design System: CopyTaste

## Overview

**Creative North Star: "The Colour Specimen Book"**

CopyTaste by tagmat is an English-language native Mac application. Forest navigation, warm paper surfaces, dark ink and a restrained terracotta accent give copied material the feel of useful specimens in a compact working library. The history index stays dense; the selected clip gets a quieter, more generous reading surface.

The implemented SwiftUI and AppKit screens define this system. Native controls, system fonts and familiar keyboard behaviour carry the interaction. The persistent storage card and footer make the memory boundary visible: history lives in RAM by default, with optional encrypted local, chosen-folder or iCloud Drive storage available in Settings.

**Key Characteristics:**

- A forest rail anchors the paper work surfaces.
- Compact sans-serif navigation surrounds spacious serif reading.
- Soft green marks selection; terracotta marks actions and pins.
- Storage and capture state stay explicit in everyday use.

## Colors

The palette pairs muted forest and warm neutrals with a single terracotta action accent. The frontmatter is the source of truth for color values.

### Primary

- **Terracotta** (`accent`): app tint, prominent actions, link text, pinned indicators and the picker's Return indicator.
- **Forest** (`rail`): navigation rail, picker search header, storage symbolism and confirmation toast.

### Secondary

- **Specimen Gold** (`brand-gold`): the brand mark's backing, with a forest overlapping-squares symbol.
- **Soft Leaf** (`selection`): selected history clips and picker rows. Selected text remains dark.

### Neutral

- **Warm Canvas** (`canvas`): main workspace and chronological history region.
- **Reading Paper** (`paper`): unselected clips, detail preview, search, Settings, picker body and status strip.
- **Dark Ink** (`ink`): primary text on light surfaces.
- **Quiet Olive** (`secondary`): descriptions, source metadata, timestamps, hints and inactive pin symbols.
- **Pale Sage** (`rail-secondary`): rail captions, secondary actions and picker close control.
- **White** (`white`): primary rail and picker-header text, prominent-action labels and toast text.
- **Paper Edge** (`divider`): structural separators and the search-field outline.
- **Rail Selection** (`rail-selected`): translucent selected navigation background.
- **Rail Card** (`rail-card`): translucent storage-card background.

The picker's active pinned-only filter uses the native yellow color. Preserve that state distinction without introducing yellow elsewhere in the palette. The rail's collection separator uses Pale Sage at 20% opacity.

**The Selection Rule.** Use Soft Leaf for selected content and translucent white for selected rail navigation; use Terracotta for actions and pin state.

## Typography

**Interface Font:** the macOS system sans serif. **Reading Font:** the system serif. **Code Font:** the system monospaced face. The brand name uses the system rounded face. Use native SwiftUI font designs rather than bundling substitute families.

The frontmatter records sizes in macOS points. Native line metrics remain intact; additional line spacing is applied only where stated below.

| Role | Application |
| --- | --- |
| Display | Two-line welcome headline. |
| Locked title | Centered privacy headline. |
| Section title | Settings introduction and image/link detail titles. |
| Preview | Ordinary copied text; add 10 points of line spacing and allow text selection. |
| Page title | Main region title with compact tracking. |
| Empty title | Unselected-detail prompt. |
| Brand | Product name in the rail; the byline is an 11-point medium caption. |
| Picker search | Plain text search on forest. |
| Settings label | Semibold section labels with an SF Symbol. |
| Body | Welcome description and link content. |
| Code | Text containing both opening and closing braces; add 7 points of line spacing. |
| Clip title | Semibold history titles; picker titles use the same size at medium weight. |
| Label | Controls, search and detail-type labels; section labels may use medium weight. |
| Caption | Descriptions, clip excerpts and source details. |
| Metadata | Footer, keyboard hints, picker source/type and clip counts. |
| Micro | Relative timestamps and history-row pin symbol. |

Welcome supporting copy adds 6 points of line spacing; locked-state supporting copy adds 5. Settings explanations and offline-link notes add 4. The rail storage description and smallest storage warning add 3. Navigation text is 13 points, regular at rest and semibold when selected. Counts use monospaced digits.

**The Reading Rule.** Reserve the large serif face for copied content and quiet introductions. Keep navigation, settings and metadata in the system sans serif.

## Layout

All dimensions are macOS points. The main window defaults to 1180 × 760 and has a 980 × 620 minimum. It uses a hidden title bar and an explicitly light color scheme. It remains a desktop three-region workspace as the window resizes; there is no collapsing sidebar or mobile breakpoint.

| Region | Geometry and rhythm |
| --- | --- |
| Navigation rail | Fixed 210 wide. Brand inset: 22 horizontally, 48 above and 34 below. Navigation and collection rows sit within 12-point horizontal margins, with 4-point gaps. Collection heading: 24-point horizontal inset, 32 above and 10 below. The storage card stays near the bottom. |
| Main header | 26-point horizontal inset, 38 above and 22 below; 16-point control gaps. Search stays 240 wide. A 1-point divider separates it from content. |
| History | Fixed 330 wide, followed by a 1-point divider. Section heading inset: 22 horizontally, 20 above and 12 below. List row insets: 4 vertically and 10 horizontally. |
| Detail | Flexible remaining width. Toolbar: 30-point horizontal inset, 22 above and 28 below. Scrolling content: 32 horizontally, 10 vertically and 24 between elements. Metadata/actions: 30-point inset, 14-point gaps, preceded by at least 24 points of space. |
| Main footer | Fixed 36 high, 24-point horizontal inset and 7-point gaps. It spans the workspace beside the rail and names storage, retention and the picker shortcut. |
| Settings | Scrollable paper surface; centered content frame has a 750-point maximum width and 32-point padding. Sections have 28-point gaps. Within a section, use 14-point gaps and a 24-point bottom inset before its divider. |
| Welcome | Centered as a group, left-aligned internally, with 40-point outer padding and 22-point gaps. |
| Locked | Centered content, 32-point outer padding and 18-point gaps. Optional iCloud passphrase field: 280 wide. |
| Picker | Fixed 650 × 460. Search header: 20-point padding and 12-point gaps. Scroll content: 10-point padding and 4-point row gaps. Hint strip: 36 high, 20-point horizontal inset. |

The rail and history keep their widths during resizing; detail absorbs the change. The upper rail scrolls as one region, keeping navigation and collections reachable above the fixed storage controls. Detail, history and Settings scroll independently. History titles and excerpts each stop at two lines. Picker titles and navigation names stop at one line. Do not imply a layout below the minimum window size.

## Elevation & Depth

The main workspace is flat. Paper, canvas, dividers and selection fills create depth without custom card shadows. The translucent storage card remains part of the rail. Native controls retain their platform rendering, focus treatment and disabled appearance.

The floating picker uses the AppKit panel's native window shadow (`hasShadow = true`), with a transparent outer window and clipped paper content. Its level is floating; it can appear across Spaces and alongside full-screen applications. There is no custom shadow radius, offset or opacity token.

## Shapes

Use the frontmatter's corner roles consistently: thumbnails, search/navigation controls, picker rows, history/storage cards, large image previews and the picker shell each have an established radius. Structural regions meet with straight edges and 1-point dividers.

The brand mark is a rounded square whose corner radius is 26% of its size. The rail mark is 34 square; the welcome mark is 54 and the picker mark is 30. Its overlapping-squares symbol is 48% of the mark size at semibold weight. Confirmation toasts use a capsule. Native buttons and secure fields keep their platform shapes.

## Components

### Buttons and menus

Prominent actions use the native bordered-prominent style with Terracotta tint and large control size for Start Capturing, Open History and Copy. Capture status uses a regular bordered control. Navigation, pins, picker close and rail actions use plain buttons. Secondary text links use the native link style. Ellipsis and collection controls use native borderless menus.

Hover, keyboard focus, pressed and disabled rendering follow native controls; there are no custom scale, hover-shadow or focus-ring effects. Every icon-only action has an accessible name. Capture and storage actions are disabled during the relevant locked, demonstration or authentication states. Destructive history clearing requires a native confirmation alert.

### Search

Main search combines a magnifying-glass symbol, plain text field and Command-F hint on paper, with a 1-point Paper Edge outline. Its 10-point padding and control radius come from the tokens. Command-F focuses the field. Search and scope changes select the first available matching clip when the previous selection no longer qualifies.

Picker search is larger and sits directly on forest with white text and caret. It gains focus as the panel appears. It displays up to the first 50 matching clips, with a query independent of main-window search.

### Navigation and storage card

Navigation rows use 10-point icon/text gaps, 20-point icon columns, 12-point horizontal padding and 10-point vertical padding. Selection adds the translucent rail fill and selected accessibility trait. Collections share the row pattern.

The bottom storage card opens the actual storage controls. It uses 14-point padding, a 19-point memory or shield symbol, a 13-point semibold heading and an 11-point description. Wording reflects RAM or encrypted storage. The footer repeats active storage and retention, or explicitly says history is locked.

**The Visible Boundary Rule.** Keep the storage card and footer truthful as storage, lock, capture and demonstration states change.

### History clips and detail

Clips use paper at rest and Soft Leaf when selected, with the clip-row radius and row inset. Their 10-point vertical rhythm separates source/time metadata, title and a two-line excerpt. Images use a cropped 42-point-high thumbnail. Double-click copies; the context menu offers Copy, Pin, collection assignment and Delete.

Detail uses paper and large selectable content. Images scale to fit. Links show an offline explanation and selectable URL; they do not fetch remote previews. Plain text uses the reading serif; text with both opening and closing braces uses the code style. Pin and overflow controls stay above the preview; source, size, collection and Copy stay below.

### Settings

Settings uses labeled sections separated by fine rules. Pickers, toggles, secure fields and buttons remain native. Storage choices expose RAM, an encrypted vault on this Mac, an encrypted vault in a chosen folder and passphrase-encrypted iCloud Drive sync. Explanatory and disabled states follow the selected storage mode. The current storage label remains visible until an applied change succeeds.

### Empty, locked and confirmation states

- **First use or empty history:** welcome mark, serif headline, explicit Start Capturing action and Privacy & storage. Capture requires opt-in. Once enabled, the primary action reads Waiting for your next copy and is disabled.
- **No filter matches:** native search-unavailable view in history. Detail shows its selection prompt when no eligible clip is selected.
- **Locked:** replace history and detail with the centered privacy state and Open History. RAM history explains it was cleared; encrypted storage explains authentication. iCloud adds a secure passphrase field. Authentication updates and disables the action.
- **Demonstration:** capture is disabled; the capture control reads Demo and the footer says Sample content · capture disabled.
- **Confirmation:** forest capsule toast, white 12-point medium text, 18-point horizontal and 12-point vertical padding, 52 points above the workspace bottom. It does not intercept input. Errors use native alerts without exposing clip payloads.

### Picker

Command-Shift-V opens the nonactivating floating picker. It starts 12 points below its destination at zero opacity, then moves and fades into place over **200 ms with ease-out timing**. Reduce Motion sets the initial offset to zero, initial opacity to one and duration to zero. Dismissal immediately orders the panel out; there is no closing animation or list transition.

The destination is centered horizontally on the pointer's screen, with its lower edge 170 points below that screen's visible-frame midpoint. The panel is movable by its background. Its paper shell has the panel radius and forest header.

Rows use 14-point horizontal and 13-point vertical padding, 12-point gaps, a 26-point kind-symbol column and the picker-row radius. Selection adds Soft Leaf and a terracotta Return indicator. Hover changes selection; arrow keys wrap through matches and scroll the chosen row into view. Search and pinned-filter changes reset to the first result. Each row has a separate accessible pin action.

Return copies the selected clip and closes the picker. Escape, close, a second shortcut invocation or loss of key status dismisses it. Explicit dismissal reactivates the previous app when appropriate. The footer continuously shows select, copy and close hints. A shortcut invoked while locked opens the main history window; the picker also has a locked fallback. Empty and no-match results use native unavailable states. Locking with the picker open dismisses it.

## Do's and Don'ts

### Do:

- **Do** use the native font designs, controls and focus behaviour already established in the app.
- **Do** keep the 210-point rail and 330-point history fixed while the reading region grows.
- **Do** use serif text for reading and system sans serif for navigation, settings and metadata.
- **Do** show real storage, capture, lock and demonstration state in visible controls.
- **Do** keep Command-Shift-V, arrow selection, Return copying and Escape dismissal discoverable.
- **Do** preserve the picker's zero-duration, zero-offset Reduce Motion path.

### Don't:

- **Don't** replace native controls with decorative web-style substitutes or add unimplemented responsive breakpoints.
- **Don't** turn every surface into a shadowed card; use paper tones and fine dividers.
- **Don't** use action color as a replacement for the selected-content fill.
- **Don't** put sensitive clip payloads in errors or diagnostic presentation.
- **Don't** imply persistence is the default or that pinning bypasses retention.
- **Don't** add animation to locked content or copy-result lists without an explicit behaviour change.
