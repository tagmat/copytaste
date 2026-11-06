# Security model

CopyTaste reduces accidental retention of sensitive copies.

## Capture boundary

Capture is off on first launch. Starting or resuming observes only subsequent clipboard changes and never imports the existing clipboard. Polling may miss rapidly replaced copies.

Before requesting text or image bytes, the monitor checks all advertised item types, the frontmost application's bundle identifier, secure-input status and application-transition timing. Private, transient and automatically generated clipboard markers reject the entire change. Credential application families and user exclusions cannot be overridden by a clipboard source hint. Unknown sources and multi-item copies are skipped. File URLs are accepted only for bounded regular-file capture, after the same source and marker checks.

The monitor also rechecks the pasteboard change count, frontmost application and secure input after reading, discarding a raced result. All processing is local. Clipboard payloads are not written to logs or diagnostics.

**Source attribution is best effort.** The pasteboard has no general, authenticated writer identity. A background process may write while an allowed app is foreground. Clipboard source markers can be forged. Ordinary passwords in unmarked browser text, unknown credential apps, obfuscated secrets and some generated credentials may pass the heuristics. Exclude apps used for sensitive data, and pause capture when necessary. Protected bundle rules live in `Sources/CopyTasteCore/CapturePolicy.swift` and must be maintained as app identifiers change.

Text is bounded to 512 KiB of UTF-8. Common token prefixes, credential assignments, private-key headers, JWT-like text, isolated 4–8 digit codes, some generated-password shapes, credential URL parameters and Luhn-valid payment numbers are rejected. These rules deliberately cause some false positives and cannot recognise all secrets. **Image content is not inspected for credentials.** Image capture is enabled in 0.2; the migration enables it for the old 0.1 default, and later explicit opt-outs persist. When enabled, metadata dimensions and compressed byte size are bounded before bitmap decoding. Images are normalised to PNG, bounded to 4 MiB, 8,192 pixels per side and 16 million pixels total. Some image metadata may survive platform decoding; do not treat re-encoding as a metadata scrubber.

## Memory mode

This is the default. Clipboard content, previews, pins and collections stay in process memory. No history file or encryption key is created in this mode. File pasting needs a temporary file URL that the destination can read, described below. Non-content preferences, such as exclusions and retention, use UserDefaults. Quitting or manual app lock releases history and key references.

Screen lock, display sleep, system sleep and session resignation suspend capture and sync. By default, history and any unlocked vault key material remain in process memory. Clipboard output, outgoing files and preview caches are cleared, and the selector hides its contents. Capture resumes only after the observed suspension reasons end, using the prior Capture setting. Resume skips the current clipboard. The optional Clear history when Mac locks or sleeps setting releases the session instead, with saved vaults requiring authentication to reopen. OS notifications are best effort and can be delayed.

Swift strings, framework image caches and OS buffers cannot be reliably zeroised. Released memory may remain recoverable until overwritten. macOS can page process memory to disk; crash reports, screenshots and system snapshots are outside the app's control. Use FileVault and keep your Mac account secure. Memory-only means the app does not persist clipboard history, not that all bytes are guaranteed to remain on physical RAM.

## Optional encrypted storage

The complete snapshot, including source names, titles and collections, is encoded and sealed with CryptoKit AES-256-GCM. Each write gets a fresh random nonce; a fixed version context is authenticated. Only ciphertext is passed to file-writing APIs. Replacement is atomic. The vault directory is restricted to mode 0700, its file to 0600, and the file is marked excluded from normal backup. Direct vault or parent-directory symbolic links are rejected. This is not a defence against a malicious local user racing filesystem changes.

The key is a 256-bit value stored through Security.framework as a non-synchronising generic Keychain item, with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Legacy macOS Keychain access control and the login keychain govern actual key access; this is not a Secure Enclave non-exportable key. The application uses LocalAuthentication's device-owner policy before opening saved history or first enabling encrypted storage. That application-level gate is not a replacement for Keychain ACLs. On an unlocked, compromised account, process instrumentation may bypass it.

A missing key, failed authentication, corrupt file or unsupported version leaves the existing vault untouched. A storage write failure pauses capture and does not fall back to plaintext persistence. Saved history starts locked on relaunch. Key references are released on manual app lock or session clearing. Changing storage removes the prior active vault after writing the destination. A copied vault requires the original Keychain item.

App-managed retention applies to pins by default, on capture, every minute while open and when reopening a saved vault. The optional pin exemption skips only the age limit. Pins still count toward the clip and byte limits. Files are not deleted while the app is closed. Removing entries or a vault is not guaranteed secure erasure on APFS, SSDs, provider backups or snapshots. Copies previously made by another application cannot be revoked.

## Clipboard output

Items copied from history carry a private marker and an origin marker. Other software may disregard these. Auto-clear removes only a still-current CopyTaste-written value, and lock or quit clears that value immediately. Newer clipboard changes are preserved. The app does not clear arbitrary user copies. When Paste on selection is enabled, it may synthesize Command-V for the original destination, as described below.

## Optional iCloud sync

iCloud mode is an explicit alternative to memory and local vaults. It uses the user's already enabled iCloud Drive directory, not an app server or CloudKit database. The shared file at `iCloud Drive/CopyTaste/history.copytaste` has a fixed format marker and random 16-byte salt, followed by an AES-256-GCM sealed state. The marker and salt are authenticated as associated data. The passphrase derives a 32-byte key through PBKDF2-HMAC-SHA256 with 600,000 iterations. Choose a long, unique phrase: a stolen file permits offline password guessing. Losing the phrase loses access. No recovery service exists.

The sync phrase is not persisted in Keychain, UserDefaults or the vault. Its UTF-8 bytes and derived key remain in memory during the sync session, including default screen-lock suspension, so independently initialised conflict versions with different salts can be decrypted using the same phrase. Both references are released on manual app lock, session clearing or quit. Swift cannot guarantee zeroisation of entered phrases or derived material. LocalAuthentication is also required when opening sync history. The device-local key protects local vaults only.

The encrypted state includes content, pin state, collection membership, deletion fingerprints and a clear-history timestamp. Merge prefers the most recently modified entry with a deterministic identity tie-break, and applies deletion boundaries to original capture dates so stale pin changes cannot resurrect removed content. Recopying after deletion creates a new capture date and can be retained again. Each merge reapplies the receiving device's content filters and retention. Device clocks must be reasonably accurate. Deletion logs are bounded; filling them pauses writes instead of dropping deletion evidence. Start a fresh shared vault after archiving or removing the old one if this boundary is reached.

NSFileCoordinator coordinates local access. Unresolved NSFileVersion conflicts are decrypted, merged and marked resolved after a successful write. Identical state does not cause a new write, avoiding continuous sync churn. Known evicted placeholders are requested for download before connecting; no fresh vault is created over those placeholders. iCloud provides transport and account protection; a local merge timestamp does not establish delivery. Availability, placeholder formats and conflict handling need live multi-device validation. Disconnecting or switching to memory does not delete cloud/provider copies. All clients knowing the phrase can decrypt and modify shared history; no separate device revocation protocol exists in this version.

A failed merge leaves pending edits and deletions in the session's bounded memory. CopyTaste retries with backoff and reports the last local merge. Pending changes survive default screen-lock suspension. Manual app lock, session clearing or quit discards them. Only explicit iCloud setup can initialise a vault. Reopening a previously configured vault requires the original file or a restored copy.

## Distribution and reporting

Local builds are ad-hoc signed with the hardened runtime. They are not notarised and are not App Sandbox containers. Do not mistake a local signature for publisher verification. Release signing and notarisation are separate, documented distribution steps. No network client, remote content fetch, telemetry or update agent is included.

To report a suspected vulnerability, contact the repository owner privately. Describe the affected version and a minimal reproduction using synthetic content. Do not send real clipboard history, tokens or vault keys. A dedicated security contact has not been designated for this early release.

## Platform references

- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication)

## File capture, previews and outgoing transfers

File URLs are handled only after metadata rejection. Only one regular file is captured, with symlinks and directories rejected. Size is checked before and after reading, with an 8 MiB cap; the history byte budget still applies. Common credential/key extensions and sensitive filenames are blocked. Recognised UTF-8 text formats pass the text secret filter, including its 512 KiB cap. Encrypted sync applies the same file-content/name limits to peer entries. Source races are checked after reading. A hostile local filesystem mutation can still race Foundation path checks; this is not a defence against a compromised account.

Image representations win over accompanying text or URLs. Disabling image capture does not silently keep that image's URL. Thumbnail decoding is bounded before bitmap allocation; PDFs are rendered from Data at thumbnail size. Generic file types use native icons. No remote preview fetch or document macro execution is performed. Binary archives/documents and images may contain secrets the app cannot identify. All peers must support the file entry kind (0.2 or newer) before using file sync.

Image text search is opt-in. Vision processes bounded images locally while the selector is open. Recognised text that matches secret heuristics is omitted from the temporary search index. The index is separate from history and is released on closing or locking the selector. Manual snippets, edited text and clip labels pass the text secret filter before saving.

Selecting Copy or Paste for a file materialises an outgoing file in a unique owner-only temporary directory. The directory is mode 0700 and file mode 0600; its path is placed on the private-marked pasteboard. Transfers expire after five minutes even when clipboard auto-clear is set to Never. Clear History, lock and quit remove owned transfers earlier. Removal is best effort and does not promise secure erasure on SSDs, snapshots or crash recovery. A receiving application may retain its own copy. A crash can leave temporary transfers for OS cleanup.

## Direct paste and permissions

Automatic paste is a separate, optional delivery action after an explicit item selection. It requires Accessibility permission; CopyTaste cannot grant that permission itself. Copy-only and demo modes never post input. The app copies first, validates the requested process, activates it, waits briefly and checks trust, secure input, foreground PID and session generation again. Events are addressed to the original PID through CGEvent.postToPid, rather than sent indiscriminately to whichever app gains focus. Locking or reopening the selector cancels an in-flight paste. No global event tap, keystroke logger or Input Monitoring entitlement is used.

Missing permission or failed destination validation leaves a copy available for manual paste. CGEvent delivery has no acknowledgement that the receiving app accepted the content; app-specific paste formats still matter. Real Accessibility approval and cross-app delivery need manual OS testing. Local ad-hoc rebuilds can require permission reapproval; use a stable Developer ID for distribution.

The pasteboard change count is checked after destination activation. A newer copy cancels the pending paste and remains intact. Batch paste builds one temporary text block from explicitly selected text or links. It uses the same output and destination checks as a single clip.

While settings are visible, CopyTaste queries its Accessibility trust and, on macOS 15.4 or later, the system pasteboard access policy. These status checks do not read clipboard contents or display permission prompts. The Allow button explicitly requests Accessibility. When the system policy blocks programmatic pasteboard access, the capture monitor skips the change before requesting item metadata or contents. The policy can be inspected separately from the Capture switch.
