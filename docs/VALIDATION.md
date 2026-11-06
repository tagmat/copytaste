# Validation — 4 November 2026

On 6 November 2026, CopyTaste 0.4.2 passed 97 tests. New regressions post lock, unlock, sleep, wake and session-switch messages through isolated notification centers. They verify retained RAM history, new capture after resume, skipped suspended-period copies, overlapping and repeated events, manual pause and lock, optional clearing, saved-vault protection and cancellation of a paste interrupted by a complete lock/unlock cycle. Pending iCloud edits also survive default suspension in an isolated file fixture. The physical Mac lock and wake sequence remains a manual check.

CopyTaste 0.3 was validated locally using macOS 26.3.1, Xcode 26.5 and Swift 6.3.2 on Apple Silicon.

For CopyTaste 0.4, 89 tests passed in the same environment. Added coverage verifies hex expansion and alpha, color filtering, atomic folder creation with clip movement, folder removal without deleting clips, and deterministic rename merging with legacy snapshots. The README color example was rendered from the native swatch component with synthetic values. Live folder interactions and cross-device delivery remain manual checks.

## Automated

85 tests passed with synthetic content and isolated native pasteboards and temporary files. New cases cover Vision recognising the rendered sample image, ephemeral OCR search, batch order and size limits, snippet creation, edit validation, pin expiry, recovery after a missing sync file and paste cancellation when a newer copy replaces the clipboard. The sync regression confirms a stale peer cannot restore the original text after the pending edit merges. The permission revocation regression confirms that a loss of trust during activation leaves the clip copied and sends no event to the test sink.

Release builds succeeded for arm64 and x86_64. The clean distribution ZIP is built and ad-hoc signed in a temporary staging directory outside folder-sync metadata. Bundle metadata and shell syntax checks passed. Test vaults, transfer fixtures and build staging directories were cleaned. No Docker resources were needed.

## Local interface review

A separately identified preview app used synthetic clips and an isolated pasteboard, with global-hot-key registration disabled. It did not restart or clear the user's live CopyTaste memory session. The selector, menu-bar settings bubble, image/PDF/text previews and file filter were inspected. The final visual pass confirmed readable dark control capsules, opaque spatial cards, mint selection, real PDF thumbnails and text-file excerpts. All source findings from the bounded review were corrected: clearing outgoing transfers/cache, filename search and distinguishable VoiceOver card labels.

In the unlocked sample session, a scroll event moved selection from a link to the next image. Show all pins revealed the two sample pins. Switching to Single orbit removed the split, and the Files filter showed formatted Markdown, coloured Swift tokens and a PDF thumbnail. The final build puts the split captions on dark surfaces and leaves room for card shadows. README screenshots show these final sample surfaces. PNG exports were checked for text, EXIF and time chunks. The GIF was assembled from reencoded pixel frames.

The Accessibility and Clipboard access rows were checked in both settings surfaces using the sample session. Live macOS permission changes still need a manual test.

The 0.3 sample session showed numbered cards, Command-B queueing two clips in order, and Command-E opening the clip editor. The Save path was checked in integration tests. Actual destination paste acknowledgement and multi-Mac transport remain manual checks.

## Not certified

Real Accessibility approval and cross-app acceptance of posted paste events require manual OS testing. Input-sink tests verify targeting and cancellation logic, not destination acknowledgement. Multi-Mac iCloud transport, actual conflict/placeholder behaviour, real Keychain prompts, OS lock/sleep signals, comprehensive VoiceOver/Full Keyboard Access, login-item approval and Intel execution still need release testing.

Developer ID signing, notarisation and public hosting have not been performed. See [distribution](DISTRIBUTION.md) and [security](../SECURITY.md).
