# Testing

Run `./scripts/test.sh` on a logged-in Mac with Xcode 16 or later. The package has no network dependencies. The scripts keep compiler module caches inside `.build`.

Pure unit tests verify private-marker handling, protected bundle families, untrusted source hints, exclusions, transition races, secret fixtures, limits, classification, search, deduplication and retention of pins. Encryption tests cover authenticated round trips, ciphertext opacity, nonce freshness, tampering, wrong keys, format versions, symbolic links and filesystem permissions. They operate in unique temporary directories and remove them after each test.

App integration tests use uniquely named pasteboards and synthetic clips. They verify copying with private markers, preserving newer clipboard changes, clearing owned values on shutdown and real collection/pin/search operations. **They never use the general pasteboard or Keychain.** A sandbox that denies the pasteboard service cannot run these integration tests; grant the test process access to the logged-in GUI session rather than interpreting nil clipboard values as an app failure.

## Manual release checks

Use a dedicated test account or only synthetic content. Do not copy real credentials for testing.

- Start the packaged app with no saved preferences. Verify memory mode and capture off. Enable capture and copy harmless text from a standard text editor. Search, pin, move and copy the entry.
- Verify the pre-existing clipboard is not imported on start or resume.
- Copy from an explicitly excluded app. No entry should appear. Adding an exclusion should remove earlier entries attributed to that app.
- Select encrypted local storage and complete the OS authentication sheet. Relaunch; no history is shown until authentication. Cancel authentication and verify the view remains locked.
- Select a temporary custom folder. Verify an encrypted file is created, the old active file is removed and an unrelated existing vault is never overwritten. Switch to memory and verify the active file is removed.
- Enable pinned-only persistence. After relaunch, only saved pins should return. Check expiry still applies to pins.
- With a disposable vault, deny write access. Capture must pause, surface an error and leave the previous vault intact. Do not modify production Keychain items for this test.
- Copy from the app, then replace the clipboard. Auto-clear and quit must preserve the newer value.
- Lock the Mac, sleep it and change login sessions. History should unload. Memory history is gone; saved history needs authentication to return.
- Verify ⇧⌘V, ⌘F, ⌘Return, ⇧⌘P, ⇧⌘L, VoiceOver labels, list keyboard navigation and a resized window.
- Enable the login item only in the test account. Verify it appears in macOS Login Items, then disable it.

Authentication, Keychain prompts, OS lock events, login-item approval and notarisation need actual OS interaction. Unit tests do not certify those integrations. The CI workflow builds both Mac architectures; Intel execution still needs an Intel test machine.

## iCloud and picker checks

The encrypted sync tests use a shared temporary file, not a live iCloud account. They cover two-client merging, pin state, collection membership, offline deletions, clear-history boundaries, re-copy after deletion, sensitive peer data, incorrect passphrases, unchanged-write suppression and collection-limit overflow.

For a real release, use two Macs with a test iCloud account and a unique sync phrase. Verify offline edits, delivery delay, evicted files, concurrent conflicts, deletion propagation, incorrect phrases and disconnecting without removing shared history. Check that no real credentials enter the test workflow. Live iCloud delivery is not certified by the local suite.

Open the sample window, invoke ⇧⌘V, search with synthetic content, navigate with arrows and Return, and verify copying stays on the sample pasteboard. With both primary and sample windows open, history commands must act on the focused model. Repeat with Reduce Motion enabled.
