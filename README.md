# CopyTaste

A little room for the good bits. **CopyTaste by tagmat** is a native, open source clipboard manager for macOS. Search text, links and images, pin the useful ones and organise them into collections.

**History stays in RAM by default.** Capture starts only after you enable it. Quitting, locking the history, screen locking or sleeping discards the in-memory session.

## Run

Requires macOS 14 or later and Xcode 16 or later (Swift 6). No third-party packages are needed.

```sh
./scripts/build-app.sh
open dist/CopyTaste.app
```

Move the app to Applications for regular use and login-item support. The local build has an ad-hoc signature. A public download needs a Developer ID signature and Apple notarisation; see [distribution](docs/DISTRIBUTION.md).

The build also creates `dist/CopyTaste-macOS.zip`, packaged from a clean staging directory. Use this archive when moving or sharing the app; folder-sync providers can attach extra Finder metadata to a loose `.app` bundle.

To explore without touching your real clipboard or storage:

```sh
open -n dist/CopyTaste.app --args --demo
```

The demo contains labelled synthetic clips, has capture disabled, uses its own named pasteboard and never opens a saved vault. You can also open a separate sample window from **Help → Explore Sample History**.

## Everyday use

- Open the animated quick picker with **⇧⌘V** from any app. Type to search, use **↑ / ↓** to choose, **Return** to copy and **Escape** to dismiss. Pin items directly in the picker.
- Open the complete history from the menu bar. The picker returns focus to your previous app; use **⌘V** to paste.
- Search with **⌘F**. Use the history list to navigate, then **⌘Return** to copy.
- Paste into your destination app with **⌘V**. No Accessibility permission is required.
- Pin clips, create collections with the sidebar **+**, and move items from the preview or context menu.
- Pause capture with **⇧⌘P**. Lock with **⇧⌘L**.
- By default, a clip copied from CopyTaste is cleared from the system clipboard after 45 seconds, only if nothing newer has replaced it.

Closing the window keeps CopyTaste running in the menu bar. Use **Quit CopyTaste** to end the session. Memory mode clears the complete history on quit or lock, including pins and collections.

## Choose what stays

Settings offers four storage locations and an optional pinned-only rule:

| Setting | Clipboard content | On quit or lock |
| --- | --- | --- |
| Memory only — default | RAM; no vault or key created | Discarded |
| Encrypted vault on this Mac | AES-256-GCM file in Application Support | Saved history remains encrypted |
| Encrypted vault in a chosen folder | AES-256-GCM file in that folder | Saved history remains encrypted |
| iCloud Drive sync | Shared, passphrase-encrypted vault in iCloud Drive | Synced history remains encrypted |
| Save pinned items only | Only pins go into the selected encrypted vault | Other clips are discarded |

Apply storage changes explicitly. CopyTaste writes the new encrypted vault before removing the old active local vault; it refuses to replace an unrelated local vault. Switching to memory removes the active local saved vault. Disconnecting iCloud leaves its shared encrypted file for other devices. File removal cannot erase copies made by backups, snapshots or a folder-sync provider.

Local encrypted storage uses a non-synchronising 256-bit Keychain key. Opening saved history requires Mac authentication. A local vault file by itself is not a portable backup: **losing the keychain means losing access to that saved history**. A chosen folder may also transfer encrypted files through its provider.

## iCloud sync

Choose **iCloud Drive · encrypted sync** in Settings and enter a separate sync passphrase of at least 16 characters. Enable the same option with the same passphrase on another Mac signed into the same iCloud account. macOS iCloud Drive must already be enabled; CopyTaste does not change your account settings.

Clips, pins and collections are merged through `iCloud Drive/CopyTaste/history.copytaste`. The payload is encrypted with AES-256-GCM before writing. Its key is derived locally from the passphrase using PBKDF2-HMAC-SHA256 (600,000 iterations and a random salt). **The passphrase is not saved and cannot be recovered.** Re-enter it after locking or relaunching. iCloud mode syncs all retained entries; pinned-only saving is available for local vaults.

The app checks for merges every six seconds while open and unlocked, coordinates file access and merges unresolved iCloud conflict versions. Deletions and clear-history boundaries travel with the encrypted data, preventing an offline peer from restoring older removed clips. macOS handles actual network delivery; “Last local merge” confirms local file processing, not delivery to another device. Offline local iCloud writes can upload later. Disconnecting does not delete the shared file. Paused capture does not pause sync; lock to unload keys and stop both.

The portable encryption and merge protocol is tested using isolated temporary files. Live delivery, account access, downloaded placeholders and conflict-version behaviour require testing with an iCloud account on two Macs. The app has no custom server, analytics endpoint or automatic update connection.

Entries expire after 7 days by default, including pins. Choose 1, 7 or 30 days and 100, 300 or 1,000 entries. A 24 MB content budget also applies. Expiration is checked during use and on reopening a saved vault; a closed app cannot run background deletions.

## Privacy controls

Protected application bundle families, private clipboard markers, secure input and uncertain foreground transitions are excluded before reading payloads. Additional filters reject common credentials, private keys, tokens, short numeric codes, credential-bearing URLs and Luhn-valid payment numbers. Add your own excluded applications in Settings; existing entries attributed to a newly excluded app are removed from active history.

Images are disabled by default because their contents are not scanned for secrets. Enable them explicitly if needed. Rich text is stored as plain text; file copies, multiple simultaneous clipboard items and oversized payloads are skipped.

macOS does not provide a trustworthy owner identity for every clipboard change. Foreground attribution and content filters cannot identify every password, especially ordinary text from a browser or background application. Exclude sensitive apps and pause capture for private workflows. Read the [security model](SECURITY.md) for the precise boundaries.

There are no app accounts, telemetry, remote previews, content logs or third-party runtime dependencies. Optional sync uses your existing macOS iCloud Drive account.

## Develop

```sh
./scripts/test.sh
./scripts/build-app.sh --universal
```

The test suite covers capture policy, secret fixtures, history limits, encrypted storage and native named-pasteboard integration. Native pasteboard tests require a logged-in macOS GUI session. Test files use unique temporary directories and are removed afterward. See [testing](docs/TESTING.md), [architecture](docs/ARCHITECTURE.md) and [contributing](CONTRIBUTING.md).

Licensed under the [MIT License](LICENSE). © 2026 tagmat.
