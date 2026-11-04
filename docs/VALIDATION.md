# Validation — 4 November 2026

CopyTaste 0.2 was validated locally using macOS 26.3.1, Xcode 26.5 and Swift 6.3.2 on Apple Silicon.

## Automated

76 tests passed with synthetic content and isolated native pasteboards/temporary files. New regressions cover mixed image/URL representations, files and symlinks, file transfer cleanup, filename search, in-memory PDF previews, selector slots, a recent clip after 100 pins, Markdown blocks, bounded Unicode-safe syntax tokens, preference migration, unknown layout fallback and destination-safe direct-paste decisions. Real keystroke injection is replaced by a test sink.

Release builds succeeded for arm64 and x86_64. The clean distribution ZIP is built and ad-hoc signed in a temporary staging directory outside folder-sync metadata. Bundle metadata and shell syntax checks passed. Test vaults, transfer fixtures and build staging directories were cleaned. No Docker resources were needed.

## Local interface review

A separately identified preview app used synthetic clips and an isolated pasteboard, with global-hot-key registration disabled. It did not restart or clear the user's live CopyTaste memory session. The selector, menu-bar settings bubble, image/PDF/text previews and file filter were inspected. The final visual pass confirmed readable dark control capsules, opaque spatial cards, mint selection, real PDF thumbnails and text-file excerpts. All source findings from the bounded review were corrected: clearing outgoing transfers/cache, filename search and distinguishable VoiceOver card labels.

The subsequent Markdown/code and split-layout additions passed source review and the automated regressions above. A locked Mac prevented refreshing their final interactive captures; wheel/trackpad behaviour and final colour/layout rendering still need an unlocked-session check. README media illustrates the previously captured single-orbit, file and bubble surfaces with synthetic samples. PNG exports were checked for text/EXIF/time chunks; the GIF is assembled from new pixel frames without source metadata.

## Not certified

Real Accessibility approval and cross-app acceptance of posted paste events require manual OS testing. Input-sink tests verify targeting and cancellation logic, not destination acknowledgement. Multi-Mac iCloud transport, actual conflict/placeholder behaviour, real Keychain prompts, OS lock/sleep signals, comprehensive VoiceOver/Full Keyboard Access, login-item approval and Intel execution still need release testing.

Developer ID signing, notarisation and public hosting have not been performed. See [distribution](DISTRIBUTION.md) and [security](../SECURITY.md).
