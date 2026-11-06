# CopyTaste follow-up work

These items are improvements or checks requiring specific OS/account conditions. They do not block publishing the source under MIT. Do not treat injected tests as certification of real device/account behaviour.

## Release validation

- [ ] Validate live iCloud delivery, offline recovery, file eviction placeholders and unresolved NSFileVersion conflicts with two Macs and a dedicated test account. Merge all pending work before sync compaction, then verify stale peers require reopening.
- [ ] Validate Developer ID Data Protection Keychain creation and legacy migration, including cancelled user-presence prompts. Ad-hoc development builds deliberately retain the documented login-keychain compatibility path.
- [ ] Complete Developer ID signing, notarisation, stapling and Gatekeeper verification before offering a trusted binary release.
- [ ] Test actual Paste from Other Apps permission transitions, including Ask, and Accessibility revocation on supported macOS versions.
- [ ] Verify physical lock/sleep/wake, fast user switching and authenticated recovery after missed notifications.
- [ ] Run the universal application on Intel hardware and complete VoiceOver/Full Keyboard Access checks.

## Product and performance

- [ ] Profile capture/exchange with 1,000 mixed text, image, file and PDF entries, including slow network volumes. Current I/O runs off the main actor and hashes are cached; document measured latency/memory baselines.
- [ ] Consider an optional encrypted local outbox for iCloud. Pending changes currently stay in memory; manual lock/quit protect them with an explicit discard choice, while sudden termination can still lose them.
- [ ] Consider on-demand rich-only RTF/HTML conversion. Unsupported representations are now counted and explained rather than silently ignored.
- [ ] Evaluate a safer event-based capture strategy for app switches. Uncertain source transitions remain intentionally rejected and counted; never guess a protected source's identity to improve capture rate.
- [ ] Consider bounded parallel preview generation and resource isolation for pathological PDFs. Rendering is asynchronous and input bytes are bounded, but framework parsing has no hard execution deadline.
- [ ] Consider immediate expiry re-evaluation after unpinning a retained old clip.
- [ ] Revisit consent for image-capture migration from the historical 0.1 default if supporting that upgrade path beyond the initial public release.
- [ ] Extend language-aware highlighting beyond Python/shell/YAML hash comments and Swift/CSS exclusions.
- [ ] Add UI automation coverage for snippet/folder editor dismissal. Safe optional bindings fix the crash found in native preview; retain an end-to-end regression once a stable runner is available.
- [ ] Record macOS-native product context in the current design-tool schema when that workflow supports macOS explicitly; preserve the existing AppKit/SwiftUI design meanwhile.

## Naming

- [ ] Keep the repository slug `copytaste` and visible attribution `CopyTaste by tagmat`. Before a broader product launch, evaluate name confusion with the existing Copy & Taste macOS app; a repository hyphen does not distinguish the product.
