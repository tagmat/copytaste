# CopyTaste

**CopyTaste by tagmat** is a native, open source clipboard utility for macOS. It lives in the menu bar. Press **⇧⌘V** and your clips spread into a floating card orbit: search, move through the cards, pin a favourite and paste it into the app you came from.

History stays in RAM by default. Capture starts only after you enable it. The menu-bar icon opens quick settings; the gear opens advanced settings when you need them.

![CopyTaste floating selector with synthetic sample clips](docs/media/selector.png)

*The optional single-orbit layout. All screenshots use fictional sample clips in an isolated preview session.*

| Keep close | Move quickly | Choose what stays |
| --- | --- | --- |
| Pinned clips on the left, newest copies on the right | Scroll, search, use arrow keys, then Return to paste | RAM by default; encrypted local, folder or iCloud options |
| Image, PDF and file thumbnails | Spring-driven cards with depth and a fly-away selection | Private-app exclusions, secret filters and retention |
| Markdown previews and syntax-coloured code | Menu-bar bubble for everyday controls | No accounts, analytics or remote preview requests |

![Synthetic interface tour of CopyTaste](docs/media/interface-tour.gif)

*A looping tour assembled from application screenshots, not a recording of the card animations. Media contains sample data only and is reencoded without source metadata.*

## Run

Requires macOS 14 or later and Xcode 16 or later (Swift 6). No third-party packages are needed.

```sh
./scripts/build-app.sh --universal
open dist/CopyTaste.app
```

The build creates `dist/CopyTaste.app` and a clean `dist/CopyTaste-macOS.zip` with arm64 and x86_64 slices. Move the app to Applications for regular use. The local build is ad-hoc signed; public distribution needs Developer ID signing and notarisation. See [distribution](docs/DISTRIBUTION.md).

The menu-bar bubble offers **Try sample clips**. Samples use an isolated pasteboard and never post paste events. You can also run:

```sh
open -n dist/CopyTaste.app --args --demo
```

## A smaller desktop workflow

- **⇧⌘V:** open or close the floating selector from another app.
- **Type:** search text, titles, source apps and file names.
- **Scroll or arrow keys:** move through the cards; **Return:** paste the selected clip.
- **Option-Return:** copy without automatic paste. **Escape:** dismiss.
- **Command-P:** pin or unpin the selection. Each card also has a pin button.
- Filter All, Pinned, Text, Links, Images or Files. The folder menu filters collections.
- Right-click a card to copy, assign a collection or delete it.

The default **Pinned + recent** layout keeps a small pin stack on the left and chronological cards on the right. Open **Show all pins** for the complete pinned collection. Choose **Single orbit** in the menu-bar bubble or advanced settings to combine everything in one chronological stream. Wheel and trackpad gestures move selection while the selector is open.

Cards fan out with staggered springs, respond to pointer movement, move through depth when selection changes and fly away on choosing. Reduce Motion removes the flight, tilt and scale animations. Controls keep a dark substrate so text remains readable over bright or dark desktops.

<details>
<summary>Quick settings and file previews</summary>

![Menu-bar quick settings using sample data](docs/media/quick-settings.png)

![File cards with a local PDF thumbnail](docs/media/files.png)

</details>

## Direct paste

**Paste on selection** is enabled by default. Open the menu-bar bubble and choose **Enable Direct Paste** to grant macOS Accessibility access. CopyTaste only sends Command-V to the original destination process after checking permission, secure input, activation and session validity. It does not install a global keystroke logger.

If access is missing, a destination disappears or focus changes, the item is copied instead and no paste is sent to an unrelated app. Copy-only remains available. The sample selector never activates a destination or sends keyboard events. Real destination support depends on the receiving app and the selected content type.

## Images, files and small previews

Version 0.2 fixes mixed clipboard items: real PNG/TIFF/JPEG/HEIC/GIF/WebP/BMP image data takes precedence over accompanying URL or text. Image capture is enabled in 0.2, including the migration from 0.1's disabled default. An explicit opt-out made in 0.2 survives relaunch. Disabling image capture skips a mixed image item completely instead of silently retaining its URL. A URL-only copy remains a link; the app never downloads the remote image.

Files are supported up to **8 MB per file**, within the **24 MB history budget**. Image files and PDFs show small thumbnails; UTF-8 text files show an excerpt; other types, including documents and archives, show the system file-type icon, name and size. A file is pasted as a file URL, not as its filename text.

Markdown clips and `.md` files preview headings, emphasis, lists, quotes and fenced code. Recognised source files and code-like clips colour keywords, strings, comments, numbers and function calls. Formatting is a bounded preview rather than a full editor or language parser. Links are inert, remote images are never loaded, and code is never executed.

Files are captured one at a time. Directories, symlinks, multi-file copies, common key/vault formats and sensitive filenames are skipped. Recognised text files also pass the secret filter and 512 KiB text limit. Binary documents and images are not scanned for every possible secret; exclude sensitive applications and pause capture for private workflows.

File contents stay in RAM or the chosen encrypted history. **Pasting or copying a file creates an owner-only temporary transfer file** for the destination. It expires after five minutes, and Clear History, lock and quit remove it sooner. That on-demand transfer is separate from history persistence. Clipboard output is otherwise cleared after 45 seconds by default, only if nothing newer replaced it.

## Choose what stays

| Setting | Storage | On quit or lock |
| --- | --- | --- |
| Memory only — default | Process memory | Session discarded |
| Encrypted on this Mac | AES-256-GCM in Application Support | Saved history remains encrypted |
| Encrypted in a folder | AES-256-GCM in your chosen folder | Saved history remains encrypted |
| iCloud Drive sync | Shared passphrase-encrypted file | Synced history remains encrypted |
| Save pinned items only | Optional rule for local encrypted vaults | Other clips are discarded |

Entries expire after 7 days by default, including pins. Choose 1, 7 or 30 days and 100, 300 or 1,000 clips. Expiration is checked during use and on reopening; a closed app cannot run background deletions. Memory mode clears pins and collections on lock or quit too. macOS may page memory to disk; use FileVault to protect your Mac.

Local vaults use a non-synchronising Keychain key. Opening saved history requires Mac authentication. A copied local vault requires the original keychain; losing that key loses access. Apply storage changes explicitly. The new vault is written before the old active local vault is removed. Backups and filesystem snapshots cannot be revoked by the app.

## iCloud sync

In advanced settings, choose **iCloud Drive · encrypted sync**, enter a unique phrase of at least 16 characters and use the same phrase on every Mac. iCloud Drive must already be enabled in macOS. Update all participating Macs to 0.2 before syncing file entries.

Clips, files, pins and collections are merged through `iCloud Drive/CopyTaste/history.copytaste`. Data is encrypted before writing using AES-256-GCM and a PBKDF2-HMAC-SHA256 key (600,000 iterations, random salt). The phrase is not saved and cannot be recovered; enter it after locking or restarting.

Merges run every six seconds while open and unlocked, coordinate file access and combine unresolved iCloud conflict versions. Deletions prevent stale peers restoring removed items. macOS handles network delivery: the local-merge time does not certify arrival on another device. Disconnecting leaves the shared encrypted file for other Macs. Paused capture does not pause sync; lock to stop both and unload the session.

The merge and encryption protocol is tested with isolated temporary files. Live delivery, account access and iCloud conflict handling still need two-Mac validation. There are no app accounts, analytics, remote previews, content logs or custom sync servers.

## Privacy and development

Private clipboard markers, credential applications, secure input, uncertain source transitions and common secret patterns are excluded before persistence. Source attribution is best effort; macOS does not authenticate every clipboard writer. Read [SECURITY.md](SECURITY.md) for the exact boundaries.

```sh
./scripts/test.sh
./scripts/build-app.sh --universal
```

Tests use synthetic content, private named pasteboards and temporary files. They never access the general clipboard, Keychain or real iCloud account, and direct-paste tests inject an event sink rather than sending real input. See [testing](docs/TESTING.md), [architecture](docs/ARCHITECTURE.md) and [contributing](CONTRIBUTING.md).

Screenshot exports are produced from the isolated sample session. `scripts/sanitize-readme-image.swift` reencodes PNG pixels, and `scripts/make-readme-gif.swift` assembles the illustrated tour without carrying capture metadata.

[MIT License](LICENSE). © 2026 tagmat.
