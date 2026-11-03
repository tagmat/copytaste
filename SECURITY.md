# Security model

CopyTaste 0.1.0 is an early release. It reduces accidental retention of sensitive copies; it is not a password vault or a defence against a compromised Mac.

## Capture boundary

Capture is off on first launch. Starting or resuming observes only subsequent clipboard changes and never imports the existing clipboard. Polling may miss rapidly replaced copies.

Before requesting text or image bytes, the monitor checks all advertised item types, the frontmost application's bundle identifier, secure-input status and application-transition timing. Private, transient and automatically generated clipboard markers reject the entire change. Credential application families and user exclusions cannot be overridden by a clipboard source hint. Unknown sources, multi-item copies and file URLs are skipped.

The monitor also rechecks the pasteboard change count, frontmost application and secure input after reading, discarding a raced result. All processing is local. Clipboard payloads are not written to logs or diagnostics.

**Source attribution is best effort.** The pasteboard has no general, authenticated writer identity. A background process may write while an allowed app is foreground. Clipboard source markers can be forged. Ordinary passwords in unmarked browser text, unknown credential apps, obfuscated secrets and some generated credentials may pass the heuristics. Exclude apps used for sensitive data, and pause capture when necessary. Protected bundle rules live in `Sources/CopyTasteCore/CapturePolicy.swift` and must be maintained as app identifiers change.

Text is bounded to 512 KiB of UTF-8. Common token prefixes, credential assignments, private-key headers, JWT-like text, isolated 4–8 digit codes, some generated-password shapes, credential URL parameters and Luhn-valid payment numbers are rejected. These rules deliberately cause some false positives and cannot recognise all secrets. **Image content is not inspected for credentials.** Images are off by default; when enabled, metadata dimensions and compressed byte size are bounded before bitmap decoding. Images are normalised to PNG, bounded to 4 MiB, 8,192 pixels per side and 16 million pixels total. Some image metadata may survive platform decoding; do not treat re-encoding as a metadata scrubber.

## Memory mode

This is the default. Clipboard content, previews, pins and collections stay in process memory. No history file or encryption key is created in this mode. Non-content preferences, such as exclusions and retention, use UserDefaults. Quitting, manual lock, display sleep, system sleep or session resignation releases history and key references. The distributed screen-lock notification is an additional signal. These OS notifications are best effort and can be delayed; they are not a cryptographic access boundary.

Swift strings, framework image caches and OS buffers cannot be reliably zeroised. Released memory may remain recoverable until overwritten. macOS can page process memory to disk; crash reports, screenshots and system snapshots are outside the app's control. Use FileVault and keep your Mac account secure. Memory-only means the app does not persist clipboard history, not that all bytes are guaranteed to remain on physical RAM.

## Optional encrypted storage

The complete snapshot, including source names, titles and collections, is encoded and sealed with CryptoKit AES-256-GCM. Each write gets a fresh random nonce; a fixed version context is authenticated. Only ciphertext is passed to file-writing APIs. Replacement is atomic. The vault directory is restricted to mode 0700, its file to 0600, and the file is marked excluded from normal backup. Direct vault or parent-directory symbolic links are rejected. This is not a defence against a malicious local user racing filesystem changes.

The key is a 256-bit value stored through Security.framework as a non-synchronising generic Keychain item, with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Legacy macOS Keychain access control and the login keychain govern actual key access; this is not a Secure Enclave non-exportable key. The application uses LocalAuthentication's device-owner policy before opening saved history or first enabling encrypted storage. That application-level gate is not a replacement for Keychain ACLs. On an unlocked, compromised account, process instrumentation may bypass it.

A missing key, failed authentication, corrupt file or unsupported version leaves the existing vault untouched. A storage write failure pauses capture and does not fall back to plaintext persistence. Saved history starts locked on relaunch. Key references are released when locking; keys are not printed or committed. Changing storage removes the prior active vault after writing the destination. A copied vault is not portable to a new Mac without the original Keychain item.

App-managed retention applies to pins too, on capture, every minute while open and when reopening a saved vault. Files are not deleted while the app is closed. Removing entries or a vault is not guaranteed secure erasure on APFS, SSDs, provider backups or snapshots. Copies previously made by another application cannot be revoked.

## Clipboard output

Items copied from history carry a private marker and an origin marker. Other software may disregard these. Auto-clear removes only a still-current CopyTaste-written value, and lock or quit clears that value immediately. Newer clipboard changes are preserved. The app does not clear arbitrary user copies or simulate paste keystrokes.

## Optional iCloud sync

iCloud mode is an explicit alternative to memory and local vaults. It uses the user's already enabled iCloud Drive directory, not an app server or CloudKit database. The shared file at `iCloud Drive/CopyTaste/history.copytaste` has a fixed format marker and random 16-byte salt, followed by an AES-256-GCM sealed state. The marker and salt are authenticated as associated data. The passphrase derives a 32-byte key through PBKDF2-HMAC-SHA256 with 600,000 iterations. Choose a long, unique phrase: a stolen file permits offline password guessing. Losing the phrase loses access. No recovery service exists.

The sync phrase is not persisted in Keychain, UserDefaults or the vault. Its UTF-8 bytes and derived key remain in memory during the unlocked sync session so independently initialised conflict versions with different salts can be decrypted using the same phrase. Both references are released on lock or quit. Swift cannot guarantee zeroisation of entered phrases or derived material. LocalAuthentication is also required when opening sync history. The original device-local key protects local vaults only; it is never uploaded to make sync work.

The encrypted state includes content, pin state, collection membership, deletion fingerprints and a clear-history timestamp. Merge prefers the most recently modified entry with a deterministic identity tie-break, and applies deletion boundaries to original capture dates so stale pin changes cannot resurrect removed content. Recopying after deletion creates a new capture date and can be retained again. Each merge reapplies the receiving device's content filters and retention. Device clocks must be reasonably accurate. Deletion logs are bounded; filling them pauses writes instead of dropping deletion evidence. Start a fresh shared vault after archiving or removing the old one if this boundary is reached.

NSFileCoordinator coordinates local access. Unresolved NSFileVersion conflicts are decrypted, merged and marked resolved after a successful write. Identical state does not cause a new write, avoiding continuous sync churn. Known evicted placeholders are requested for download before connecting; no fresh vault is created over those placeholders. iCloud provides transport and account protection; a local merge timestamp does not establish delivery. Availability, placeholder formats and conflict handling need live multi-device validation. Disconnecting or switching to memory does not delete cloud/provider copies. All clients knowing the phrase can decrypt and modify shared history; no separate device revocation protocol exists in this version.

## Distribution and reporting

Local builds are ad-hoc signed with the hardened runtime. They are not notarised and are not App Sandbox containers. Do not mistake a local signature for publisher verification. Release signing and notarisation are separate, documented distribution steps. No network client, remote content fetch, telemetry or update agent is included.

To report a suspected vulnerability, contact the repository owner privately. Describe the affected version and a minimal reproduction using synthetic content. Do not send real clipboard history, tokens or vault keys. A dedicated security contact has not been designated for this early release.

## Platform references

- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [LocalAuthentication](https://developer.apple.com/documentation/localauthentication)
