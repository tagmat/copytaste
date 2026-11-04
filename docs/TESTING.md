# Testing

Run `./scripts/test.sh` on a logged-in Mac with Xcode 16.3 or later. Compiler caches stay inside `.build`. Tests use synthetic text, generated images/PDFs, isolated temporary files and uniquely named pasteboards. They never use the general clipboard, Keychain or a real iCloud account. Direct-paste tests inject activation and event delivery. They never send real input.

Coverage includes source/private-marker rejection, content filters, mixed image-and-URL priority, disabled-image skip, file names/contents and symlink rejection, retention, deduplication, filename search, private transfer permissions and cleanup, PDF thumbnails, circular selector slots, recent clips after 100 pins, Markdown blocks, bounded Unicode-safe tokenisation, settings migration, unknown layout fallback and opt-out persistence, destination changes, secure input, missing permission and cancellation during activation. Encryption/sync tests cover authenticated round trips, tampering, nonces, file modes, independent salts, offline deletions, clear boundaries, collection limits and recovery.

A shell sandbox denying macOS pasteboard services cannot run native pasteboard tests; nil values in that environment do not establish an app failure. Use the logged-in GUI service context with isolated named boards.

## Manual release checks

Use synthetic data and a dedicated account for permission tests.

- Launch with fresh preferences: only the menu-bar interface should appear; capture is off and storage is memory. The gear should be the deliberate path to an advanced settings window.
- Copy an image offering both bitmap data and URL text. It must appear as Image and copy back as PNG. Disable images and verify the whole mixed item is skipped.
- Copy a PDF, text document and archive individually. Check PDF/image thumbnails, text excerpts and native icons. Search by filename. Folders, symlinks, credential/key files and oversized files must be skipped.
- Grant Accessibility through the explicit quick-settings action. From a disposable text document, open the selector with ⇧⌘V, choose a harmless clip and verify it is pasted automatically. Test image/file destinations that accept those paste types. Denied permission, secure input or changing apps must preserve copy-only fallback without pasting elsewhere.
- With advanced settings visible, grant and revoke Accessibility and verify the status updates. On macOS 15.4 or later, change Paste from Other Apps to Blocked and verify the clipboard status updates and new synthetic copies are skipped. After restoring access, verify only subsequent copies are captured.
- Test arrow and wheel/trackpad navigation, Return, Option-Return, Command-P, pin/type/collection filters, hover movement, VoiceOver labels and Reduce Motion. Switch between Pinned + recent and Single orbit. With 100 pins, a new unpinned clip must remain reachable. Demo must never activate another process or post paste input.
- Preview Markdown headings/lists/fenced code and source files containing comments, strings and Unicode. Ensure previews do not activate links, fetch images or execute code.
- In the sample selector, add two text clips with Command-B and verify the review order. Switch the separator, then copy the batch. Verify Command-1 through Command-9 select the clips shown by the card hints. Create a snippet with Command-N and edit a clip with Command-E.
- Enable Search text in images and search for `Golden hour study` in the sample session. The search should return the palette image. Close the selector to discard the OCR index and open it again to test rebuilding.
- In a disposable local sync fixture, move the vault file out of the way. Verify edits stay visible and sync reports pending changes. Restore the same file and choose Sync Now to verify the edits merge.
- Select a file, then Clear History or lock. Verify the owned temporary transfer is removed and newer clipboard values are preserved.
- Exercise encrypted local/custom-folder storage, cancelled authentication, missing Keychain, failed writes, retention and screen/session/sleep locking with disposable vaults.
- Use two Macs with a test iCloud account for real delivery, offline changes, placeholder downloads, conflict versions and deletion propagation. Update all peers before syncing file entries.
- Test login-item approval, Developer ID signing, notarisation and Intel execution separately.

These platform permission, delivery and accessibility checks are not certified by injected unit tests. See [validation](VALIDATION.md) for checks actually completed.
