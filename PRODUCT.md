# CopyTaste

## Platform
Native macOS desktop.

## Stack
SwiftUI and AppKit, a local Swift package, macOS 14 or later. No third-party runtime dependencies.

## Users and purpose
People who reuse copied material during daily Mac work. Retrieve useful text, links, images and files while avoiding retention of sensitive copies.

## Product commitments
- CopyTaste is the product name; tagmat is the brand.
- English-language native interface.
- History remains in RAM by default. Offer optional persistence choices.
- Exclude credential applications and deliberately sensitive clipboard content.
- Open source under the MIT License.

## Implementation scope
Bounded history, filename and text search, pinned entries, collections, global shortcut, menu-bar quick settings, pause, screen lock handling, expiration and clipboard auto-clear. Real image representations take precedence over accompanying links. Bounded single-file capture includes thumbnail/text/icon previews, local Markdown rendering and syntax-coloured code. Optional authenticated encrypted local or custom-folder storage, optionally restricted to pinned items. Optional passphrase-encrypted iCloud Drive sync for clips, pins and collections. A spatial card selector opens on Command-Shift-V, supports keyboard and scroll selection, and offers pinned-left/recent-right or a single chronological orbit. The app lives in the menu bar; quick settings open in an anchored popover, and only advanced settings use a regular window. Selecting a clip pastes it into the previous app when Accessibility access is granted; copy-only remains available.

## Principles
Drop ambiguous captures. Filter before persistence. Do not log clipboard payloads. Pins obey retention. First launch requires capture opt-in. Demonstration mode uses synthetic data, an isolated pasteboard and no saved vault.
