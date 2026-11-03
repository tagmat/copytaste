# Architecture

CopyTaste is a Swift 6 package with no external dependencies. `CopyTasteCore` contains value types, capture policy, bounded history operations and encrypted file I/O. The executable contains the SwiftUI interface and AppKit, Carbon, Security, LocalAuthentication and ServiceManagement adapters.

## Data path

1. `ClipboardMonitor` observes the change count every 400 ms, only after opt-in and while unlocked.
2. The metadata gate runs before payload access, rejecting private markers, excluded apps, secure input, source transitions, files and multiple items.
3. Text is checked for size and known sensitive shapes. Optional images are bounded and decoded locally. A final state check discards raced reads.
4. `AppModel` deduplicates by a SHA-256 content fingerprint and applies age, count and byte limits.
5. In memory mode, the resulting snapshot replaces process state. No file or key adapter is called.
6. With persistence enabled, the selected subset is encrypted and atomically saved before replacing visible state. Failure pauses capture. Persisted-only pins do not change the in-memory search experience.

## Persistence

`VaultSnapshot` version 1 contains entries and collections. All content and content metadata are encrypted together. The local path is `~/Library/Application Support/net.tagmat.copytaste/history.vault`; custom storage uses `<chosen folder>/CopyTaste/history.vault`. UserDefaults holds only preferences, including storage selection, retention and bundle exclusions.

`KeyStore` creates a non-synchronising 32-byte Keychain item only when optional persistence is selected. It never recreates a missing key for an existing vault. `EncryptedVault` does not know how to create keys or authenticate; those duties belong to the application adapter. LocalAuthentication protects opening saved history at the application layer.

`AppModel` is main-actor isolated. The change-count protocol and conditional auto-clear prevent stale clipboard operations from overwriting a newer copy. Storage work is synchronous and bounded; a large encrypted snapshot may briefly delay the interface. Moving file I/O to a serial actor is a future performance improvement, not a reason to make capture bypass a failed write.

## Locking and lifecycle

Screen/session/sleep notifications stop the monitor, clear owned clipboard output and release the in-memory snapshot and key. Saved vaults remain encrypted. Memory sessions cannot be reconstructed after lock. Relaunch starts saved storage locked; authentication precedes loading. A lock-generation counter prevents authentication completing across a later lock from reopening the history.

The global shortcut uses a registered Carbon hot key instead of a global keystroke monitor. Copying does not simulate events. The menu-bar item restores the main window after closing. Login-item registration is explicit and uses the packaged application's `SMAppService`.

## Interface

The navigation rail scopes history; the chronological list selects an entry; the detail pane previews and copies it. Settings replaces the work area without creating a separate modal workflow. Every image or link preview is local. The demo is a separate in-memory session with an isolated named pasteboard and labelled synthetic content.

## Quick picker and encrypted sync

A nonactivating floating NSPanel opens on ⇧⌘V with a short position/opacity animation, respecting Reduce Motion. It focuses its search field, supports arrow navigation, pins and Return-to-copy, then restores the previous application. Demo and primary pickers hold separate models and pasteboards; menu commands resolve the key window at action time. Standard ⌘V remains available for the destination app.

`CloudVault` uses iCloud Drive's already-enabled CloudDocs folder. A portable key is derived from a user-entered phrase through system CommonCrypto PBKDF2-SHA256, and the state is sealed with CryptoKit AES-GCM. The phrase is not saved. A six-second timer and writes exchange state through NSFileCoordinator, merging NSFileVersion conflicts. Deletion fingerprints, a clear boundary and modification timestamps support offline convergence. Bounded collection and deletion logs are checked before replacing the file. Unchanged state does not trigger another encrypted write. Local Keychain vaults remain a separate storage choice.
