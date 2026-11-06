# Validation — 7 November 2026

CopyTaste 0.5.0 was checked on macOS 26.3.1, Xcode 26.5 and Swift 6.3.2 on Apple Silicon. The public source requires macOS 14+ and Xcode 16.3+.

## Automated checks

- 121 XCTest tests passed with `./scripts/test.sh -Xswiftc -warnings-as-errors`. Fixtures use synthetic content, private named pasteboards, injected authentication/key providers and temporary files. The tests never access the general clipboard, real Keychain or a real iCloud account.
- Coverage includes 2,500 automatic captures without deletion-log growth; safe compaction and stale-peer rejection; full-log recovery; local retention/exclusion scope; same-time metadata conflicts; missing local vaults; settings recovery and authentication races; pin byte priority; environment/key filenames; ordinary-text false positives; NFC/NFD phrases and actual older-format ciphertext; activation accounting; unsupported representations; short-screen frames; native URL reading and language-aware highlighting.
- `./scripts/test-sandbox-transfer.sh` passed with an ad-hoc signed App Sandbox reader. The reader reported `directRead: false`, `urlReceived: true`, `pasteboardRead: true`. All data was synthetic and transferred through a private pasteboard. Test staging and transfer files were removed.
- Release builds succeeded for arm64 and x86_64 with warnings treated as errors. The build verified the signature and executable bit after extracting `CopyTaste-macOS.zip` into a clean temporary directory. A loose app inside a folder-sync provider may still receive incompatible Finder metadata; distribute the ZIP.
- Gitleaks scanned all committed history without a finding after applying the exact path-and-value exception for the deliberately invalid JWT fixture. Current publication files, relative documentation links, shell syntax and bundle metadata were also checked.
- No Docker resources were required.

## Native preview

A separate preview bundle used its own app identity, synthetic clips, an isolated pasteboard and no global shortcut registration. It did not restart or clear the user's regular clipboard session.

The spatial selector and quick settings were inspected against the existing screenshot fixtures. Async image/PDF previews appeared; controls remained readable on their dark surfaces. Opening New Snippet and saving a `2026` title with synthetic prose returned to the selector, increased the count from 12 to 13 and showed the new snippet pinned. The first native pass exposed a SwiftUI optional-binding crash on editor dismissal; safe bindings fixed it and the follow-up save succeeded. The same binding fix applies to folder editing.

README images and the GIF remain synthetic sample captures. Their PNG metadata was checked for personal text, EXIF and timestamps, and GIFs contain only normal loop/frame-control extensions. The MIT LICENSE remains at repository root.

## Not certified by these checks

Live two-Mac iCloud delivery, eviction placeholders and provider conflict handling; actual Accessibility/Paste from Other Apps permission transitions; physical lock/sleep/wake and fast user switching; Developer ID Keychain prompts/migration; full VoiceOver/Full Keyboard Access coverage; login-item approval and Intel hardware execution still need release validation. They are tracked in [TODO](../TODO.md).

Developer ID signing, notarisation and public binary release were not performed. Private vulnerability reporting was enabled and verified for [tagmat/copytaste](https://github.com/tagmat/copytaste). See [distribution](DISTRIBUTION.md) for the source and binary release steps, and [review resolution](REVIEW-RESOLUTION.md) for dispositions.
