# Distribution

The public source repository is [tagmat/copytaste](https://github.com/tagmat/copytaste), licensed under MIT. Publishing source does not require a signing certificate. Local development builds are ad-hoc signed; a trusted binary release additionally needs Developer ID signing, notarisation and stapling.

## Build and verify

Use macOS 14 or later and Xcode 16.3 or later:

```sh
./scripts/test.sh -Xswiftc -warnings-as-errors
./scripts/test-sandbox-transfer.sh
./scripts/build-app.sh --universal
```

The build creates `dist/CopyTaste.app` and `dist/CopyTaste-macOS.zip` with arm64 and x86_64 slices. It stages and signs outside folder-sync providers, replaces old generated output, then extracts the ZIP into a clean temporary directory to verify its signature and executable bit. The ZIP is the distribution artifact; a sync provider may attach incompatible Finder metadata to the loose `.app`.

CI performs these checks and uploads the already-built ZIP, preserving executable permissions. It scans committed history for secrets with the narrow synthetic-fixture exception in `.gitleaks.toml`. Action revisions are pinned to reviewed commits.

## Developer ID release

Use a Developer ID Application certificate belonging to the publisher:

```sh
COPYTASTE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/build-app.sh --universal
xcrun notarytool submit dist/CopyTaste-macOS.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
```

A certificate-signed build sets `CopyTasteDataProtectionKeychain` in its bundle. That enables Data Protection Keychain storage with user-presence access control and verified migration of an existing legacy key. Ad-hoc development builds retain the documented login-keychain compatibility path. Exercise signed Keychain creation, cancellation and migration on a dedicated release-test account before distribution.

After notarisation, extract the submitted ZIP into a clean, unsynchronised staging directory, staple that application and repackage it. Do not publish the original unstapled archive:

```sh
stage=$(mktemp -d "${TMPDIR:-/tmp}/copytaste-notarise.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto -x -k dist/CopyTaste-macOS.zip "$stage"
xcrun stapler staple "$stage/CopyTaste.app"
codesign --verify --deep --strict "$stage/CopyTaste.app"
spctl --assess --type execute --verbose "$stage/CopyTaste.app"
ditto -c -k --keepParent --norsrc --noextattr "$stage/CopyTaste.app" dist/CopyTaste-macOS.zip
```

Create the notarisation profile separately using Apple tooling. Never commit credentials, signing private keys, real clipboard vaults or notary secrets. Keep the bundle identifier and signing identity stable; changing them can affect Keychain access, Accessibility and Login Items. No updater is included.

## Source publication

Before the first push, verify all branches intended for publication use the chosen GitHub author email, the full-history secret scan passes, and only source/docs/test fixtures are tracked. The repository slug is `copytaste`; the visible product name is CopyTaste by tagmat. Keep the MIT LICENSE and screenshot assets with the source.

Private vulnerability reporting is enabled for the repository. Release-specific manual validation is tracked in [TODO](../TODO.md); the review outcomes and known tradeoffs are in [review resolution](REVIEW-RESOLUTION.md).
