# Review resolution — 0.5.0

The pre-publication reviews were checked against the source. Confirmed safety, data-loss and correctness defects are fixed; lower-priority product choices and platform-dependent checks are tracked in [TODO](../TODO.md).

| Finding | Resolution | Evidence |
| --- | --- | --- |
| Pin byte priority | If a pin cannot fit, smaller unpinned clips cannot displace it. Pins still obey hard capacity. | Pin-overflow regression with valid 8/8/7/2 MiB file fixtures. |
| Environment and key filenames | `*.env`, `.env.*` and `.ppk` join protected files. | Filename/content rejection tests. |
| Missing local vault | Unlock requires the existing file and original key; only explicit setup can initialise storage. | Missing-file test asserts no replacement or key creation. |
| Missed resume notification | Recover Session authenticates and verifies an active, unlocked console session. Silent unlock failure is explained. | Active/inactive recovery and overlapping suspension tests. |
| Sandbox file paste | Native NSURL pasteboard representations preserve access handoff and private markers. | A signed App Sandbox reader fails direct access and succeeds after consuming the private pasteboard URL. |
| Unicode sync phrase | NFC derivation, with legacy raw/NFD decryption before upgrade. | Canonical-equivalence test and an actual CTSYNC01/NFD encrypted fixture. |
| Shared deletion-log growth | Automatic pruning never creates tombstones. Clear removes covered evidence; explicit maintenance archives ciphertext and changes generation. No unsafe age-only tombstone expiry. | 2,500-copy simulation, full-log maintenance and stale-peer resurrection regressions. |
| UI blocking from I/O/KDF/hash | VaultWorker owns serial background persistence/exchange. File/image/PDF work is asynchronous; fingerprints cache content, and local writes coalesce. | Full test/build checks; larger-volume profiling remains in TODO. |
| Local retention/exclusions deleting peer data | Local preferences project the bounded shared state; explicit Delete/Clear propagate. The UI and privacy documentation explain the scope. | Peer-history projection test. |
| Storage preference race | Unrelated preferences are read after authentication; transitions suppress queued old writes. New preferences flush before old-file removal. | Pausing capture and enabling clear-on-lock during injected authentication are preserved. |
| Equal-time shared edits | The same entry identity uses deterministic metadata ordering when timestamps tie. | Commutative merge regression. |
| Aggressive secret heuristics | Paths, email, years and version/source identifiers are accepted; generated shapes require stronger evidence. Manual ambiguous numeric shapes are allowed; known credentials remain blocked. | Positive/negative policy table. |
| App-switch copy loss | Retain fail-closed attribution, poll every 150 ms and count/explain skipped pending changes. | Activation accounting test; safer event-based collection is in TODO. |
| Unreadable preferences | Independent field recovery preserves readable exclusions/storage, pauses capture and backs up original bytes. | Mixed-type and unknown-storage regressions. |
| Offline quit/manual lock | Flush on normal quit; Keep Open/Keep Unlocked is the default when work is pending. Automatic clearing remains an explicit privacy choice. | Pending sync fixtures and native application termination/discard code. A durable outbox is in TODO. |
| Hidden errors/capture state | Selector error/status banners, menu-bar symbols and copy failure reopening expose actionable state. | Native sample selector inspection; broader accessibility checks are in TODO. |
| Keychain authentication | Signed distribution builds opt into user-presence Data Protection Keychain storage and verified legacy migration. Development builds retain compatibility. | Code path and packaging flag; actual signed Keychain prompts require release validation. |
| Snippet lifetime | New snippets start pinned; the editor explicitly explains retention and the pin-age setting. | Editing/creation tests and native editor inspection. |
| Image/file precedence and decoding | Bitmap representations win over file/text URLs. ImageIO normalisation is bounded and runs off actor. | Mixed image/file URL regression and existing mixed URL/image tests. |
| Cloud permissions and conflicts | Owner-only directories/files; adopt the remote salt and cache derived keys. Remove individual resolved conflict versions after successful persistence. | File-mode and independent-salt tests; real provider conflicts remain in TODO. |
| Rich-only representations | Unsupported copies now increment the skipped count and explain the reason. | RTF-only rejection test. |
| Color words | Unprefixed six-character colors require a digit; `#facade` remains valid. | Word/color regression. |
| Highlighting | Hash comments depend on language; Swift directives and CSS colors remain code. | Language-specific token tests. |
| Repeated selector work | Matching results refresh only when history/query/filter/layout/OCR inputs change. | Source inspection plus search/filter tests. |
| Stale transfers after a crash | Startup removes only expired, owned 0700 UUID transfer directories. | Ownership/age constraints in the cleanup path; no global sweep of current transfers. |
| Stale distribution files | Replace the generated app bundle and verify a clean ZIP extraction. | Universal build, signature and executable-bit checks. |
| CI and publication | Pinned action SHAs, warnings-as-errors, secret scanning, sandbox-reader test and ZIP artifact upload. Local credentials/tool state are ignored. | Local equivalents of all CI commands. Remote CI awaits publication. |
| Documentation drift | Requirements, version, retention scope, recovery and binary-distribution limits are aligned. README screenshots and MIT LICENSE are retained. | Relative-link/metadata checks. |
| Editor close crash found in native preview | Replace force-unwrapped optional SwiftUI bindings with safe bindings that remain valid during dismissal. | Native follow-up successfully created and saved a pinned snippet with a year title; durable UI automation is tracked in TODO. |

The source can be published independently of notarisation. Real iCloud delivery, signed Keychain prompts, OS permission transitions and Intel execution are explicitly not certified by unit tests.
