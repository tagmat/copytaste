# Validation — 4 November 2026

Local validation used macOS 26.3.1, Xcode 26.5 and Swift 6.3.2 on Apple Silicon.

## Automated checks

- 48 unit and native integration tests passed with synthetic data.
- Release builds succeeded for arm64 and x86_64; the distribution binary contains both slices.
- The clean ZIP was extracted into a temporary directory and its ad-hoc signature verified with `codesign --verify --deep --strict`.
- Bundle metadata passed `plutil`; shell scripts passed `bash -n`; staged changes passed `git diff --check`.
- Temporary test vaults and packaging/verification directories were removed. Native macOS checks required no Docker resources.

## Interface checks

The packaged app launched with memory storage selected and capture off. First-launch and locked views were inspected. Sample history was isolated from real storage and the general pasteboard. Search, pin filtering, accessible row selection, detail previews, the minimum-size scrolling sidebar and the iCloud setup view were inspected.

Command-Shift-V opened the picker. With synthetic sample clips, search followed by Down and Return copied to the isolated sample pasteboard and dismissed the panel. The floating panel's light search prompt and default first-item highlight were visually checked. The completed local/demo interface review had no remaining required fixes in its scoped final pass.

## Remaining release validation

Live iCloud network delivery and conflict versions need a two-Mac account test. Portable encryption, independent initialisation salts, deletion merging and recovery were tested with local temporary files. OS authentication, real Keychain access, sleep/lock notifications, Login Items, Intel execution and comprehensive VoiceOver/Full Keyboard Access were not end-to-end certified. Source and tests cover their supporting logic but do not replace platform interaction.

The build is locally ad-hoc signed. Developer ID signing, notarisation and public hosting have not been performed. See [distribution](DISTRIBUTION.md) and [security](../SECURITY.md) before publishing a release.
