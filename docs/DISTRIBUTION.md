# Distribution

Local development builds use an ad-hoc signature and hardened runtime. They are useful for local review, but do not establish a verified publisher or pass public Gatekeeper distribution requirements.

## Build

```sh
./scripts/build-app.sh --universal
```

This creates `dist/CopyTaste.app` and `dist/CopyTaste-macOS.zip` with arm64 and x86_64 slices, a native icon and application metadata. Signing and ZIP packaging happen in a temporary staging directory outside folder-sync providers, with resource forks and extended attributes excluded from the archive. Build output is ignored by Git. Use the ZIP for distribution; a folder provider may attach incompatible Finder metadata to a loose application bundle.

For a release, use a Developer ID Application certificate belonging to the publisher:

```sh
COPYTASTE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/build-app.sh --universal
ditto -c -k --keepParent --norsrc --noextattr dist/CopyTaste.app dist/CopyTaste.zip
xcrun notarytool submit dist/CopyTaste.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
xcrun stapler staple dist/CopyTaste.app
spctl --assess --type execute --verbose dist/CopyTaste.app
```

Create the notarisation profile separately using Apple's tooling. Do not put credentials, signing identities' private keys or notary secrets in the repository. Repackage after stapling before publishing. Keep the bundle identifier and signing identity stable; changing them can affect Keychain access and Login Items.

Developer ID signing, notarisation and public hosting are not performed by the local build. No updater is included. Avoid renaming or moving the installed app while testing login-item registration.
