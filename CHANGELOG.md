# Changelog

## 0.5.0

- Keep missing vaults intact and preserve privacy preferences changed during authentication.
- Keep sync usable during normal long-term capture, with encrypted archival maintenance for full deletion logs and protection against stale peers restoring deleted clips.
- Keep per-Mac retention and exclusions local; explicit deletion and clearing continue to propagate.
- Support canonically equivalent sync phrases and migration from older encrypted files. Update every syncing Mac before opening a shared vault with 0.5.
- Move encryption, coordination, decoding and previews off the UI actor, cache fingerprints and coalesce local writes.
- Deliver files to sandboxed apps through native URL handoff and clean up expired transfers after crashes.
- Add authenticated session recovery, visible errors and pending-change protection on lock/quit.
- Preserve readable settings after partial corruption, reject environment/key files and reduce ordinary-text filter false positives.
- Fix editor dismissal, color-word detection, pin byte priority, highlighting and short-screen placement.
- Prepare the public MIT source distribution with pinned CI actions, secret scanning, verified universal ZIPs and documented platform validation limits.
