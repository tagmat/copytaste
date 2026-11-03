# CopyTaste

## Platform
Native macOS desktop.

## Stack
SwiftUI and AppKit, a local Swift package, macOS 14 or later. No third-party runtime dependencies.

## Users and purpose
People who reuse copied material during daily Mac work. Retrieve useful text, links and images while avoiding retention of sensitive copies.

## Product commitments
- CopyTaste is the product name; tagmat is the brand.
- English-language native interface.
- History remains in RAM by default. Offer optional persistence choices.
- Exclude credential applications and deliberately sensitive clipboard content.
- Open source under the MIT License.

## Implementation scope
Bounded history, full text search, pinned entries, collections, global shortcut, menu bar access, pause, screen lock handling, expiration and clipboard auto-clear. Optional authenticated encrypted local or custom-folder storage, optionally restricted to pinned items. Optional passphrase-encrypted iCloud Drive sync for clips, pins and collections. An animated nonactivating picker opens on Command-Shift-V. Pasting uses the destination app’s standard Command-V.

## Principles
Drop ambiguous captures. Filter before persistence. Do not log clipboard payloads. Pins obey retention. First launch requires capture opt-in. Demonstration mode uses synthetic data, an isolated pasteboard and no saved vault.
