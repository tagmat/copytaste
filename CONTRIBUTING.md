# Contributing

Use Xcode 16 or later, Swift 6 and macOS 14 or later. Build and test with the scripts in `scripts/`. No dependency installation is required.

Use Conventional Commits, for example `fix: reject private clipboard markers` or `feat: add a history filter`. Keep commits focused and use the configured Git author.

Changes to capture, persistence, retention or clipboard ownership need tests with synthetic fixtures. Never include real passwords, clipboard captures, Keychain exports or personal vault files. Use a uniquely named NSPasteboard in integration tests; never the general clipboard.

Keep the interface in English, preserve tagmat branding and follow native macOS keyboard and accessibility conventions. Controls must perform their stated action and have accessible names. The repository and product describe CopyTaste on its own terms.

Before submitting:

```sh
./scripts/test.sh
./scripts/build-app.sh --universal
```

Include what changed, why it matters and the checks actually run. Security-sensitive reports belong in the private process described in [SECURITY.md](SECURITY.md).
