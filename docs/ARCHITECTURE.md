# Architecture

CopyTaste is a Swift 6 package with no external dependencies. `CopyTasteCore` owns the value types, privacy policy, bounded history, encrypted local file I/O and encrypted sync state. The executable provides native macOS adapters and the interface.

## Capture

`ClipboardMonitor` polls the change count every 400 ms only while enabled and unlocked. Starting/resuming skips the existing clipboard. Source application, all advertised private markers, secure input and transition timing are checked before payload access. Changed source or clipboard state after reading discards the result.

A single regular file URL is handled through size, symlink, credential-name and text-content filters. Otherwise image bytes take priority over an accompanying URL/string. Supported bitmaps are dimension-checked before decoding and normalised to PNG. Plain strings and URL-only representations are classified last. The app never downloads an image merely because its URL was copied.

Entries deduplicate by content fingerprint, including file bytes and filename, then obey age/count/byte limits. Search includes filenames. `Preferences` uses compatible decoding with explicit 0.2 image-default migration; subsequent opt-outs persist.

## Presentation

`CopyTasteApp` has a Settings scene, with no launch-time document window. `AppDelegate` owns the model, menu-bar item, transient NSPopover, global hot key, picker and advanced-settings window controller. The app runs with accessory activation policy and LSUIElement metadata.

The selector is a transparent, nonactivating NSPanel. SwiftUI positions up to seven real clipboard cards around the selected index using circular slots, perspective, spring motion, staggered entry and exit flight. The default layout places a small pinned stack on the left and chronological recent cards on the right; a presentation preference selects a combined chronological orbit instead. Matching entries retain the full bounded history, so pins cannot displace recent results through a separate display cap. Search/filter/hint surfaces combine native material with a dark substrate. Keyboard focus, arrow navigation, copy-only, pinning, filters and collection assignment operate on the same retained history. A local scroll monitor accepts wheel/trackpad events only from the open picker window, ignores momentum and advances selection. Reduce Motion suppresses spatial animation. Preview mode has a separate app identity, isolated pasteboard and no hot-key registration, allowing development without restarting a live memory session.

The clip editor and ordered batch share the selector's panel. Batch selection stores IDs and resolves them against current history. Saving edited text assigns a new identity and records the prior fingerprint's deletion during sync. Labels and unchanged bodies preserve their identity. An optional search index recognises bounded images on a serial Vision actor and stays inside the selector view. The panel releases its hosting view on dismissal.

`PreviewCache` bounds in-memory bitmap and PDF thumbnails. PDFDocument stays alive while PDFPage renders. Generic files use system type icons. No preview file is written merely to render the selector.

`PreviewFormatting` bounds Markdown parsing and syntax tokenisation to 8,000 characters. Markdown blocks render as native SwiftUI text; inline links are removed and images are never fetched. Code token UTF-16 ranges are converted to SwiftUI AttributedString ranges for colouring. Known file extensions take precedence over text heuristics. These inert previews do not execute code or embed a browser.

## Delivery

`PasteService` receives an immutable destination PID and injected OS operations. It copies first, then checks permission, secure input, destination activation and a generation token, waits for focus, rechecks, and posts Command-V to that PID. Copy-only and demo modes never post input. The selector's generation counter cancels delayed work when dismissed/reopened or locked. Delivery lacks acknowledgement that an app accepted a given format.

File paste materialises a unique mode-0700 directory and mode-0600 file through `TransferFileStore`. Its URL is written with private/origin markers. It expires after five minutes, or sooner on Clear History, lock or quit. This on-demand transfer is separate from in-memory history. Other clipboard output is conditionally cleared only if its change count still matches.

## Persistence and lifecycle

Memory mode never invokes a history file or key adapter. Local vaults encrypt the complete snapshot with AES-256-GCM before atomic writes; their non-synchronising key uses Security.framework. LocalAuthentication gates reopening saved history.

Optional iCloud Drive sync uses a separate passphrase-derived portable key, coordinated file access, version-conflict merging, modification timestamps, deletion fingerprints and a clear boundary. The original phrase material is held only while unlocked to derive keys for independently initialised salts. File entries require 0.2-capable peers. The cloud path is the user's already-enabled iCloud Drive directory, not a custom server.

In sync mode, the model stages accepted mutations in its current in-memory snapshot and keeps their tombstones until exchange succeeds. Failures leave the state visible, record the reason and schedule a bounded retry. A successful local merge clears the pending status. Reopening requires the existing vault. Only explicit setup may create one.

Lock/session/sleep signals stop capture, clear owned clipboard output and temporary transfers, purge preview caches and release history/key references. Saved vaults remain encrypted. UserDefaults stores preferences only. Authentication and generation checks prevent delayed work reopening or pasting after a later lock. See [security](../SECURITY.md) for limits and [testing](TESTING.md) for evidence.
