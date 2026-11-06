#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
stage=$(mktemp -d "${TMPDIR:-/tmp}/copytaste-sandbox-test.XXXXXX")
trap 'rm -rf "$stage"' EXIT
swiftc -warnings-as-errors Sources/CopyTaste/FilePasteboardWriter.swift Tests/Fixtures/SandboxTransfer/main.swift -o "$stage/Probe"
app="$stage/Reader.app"
mkdir -p "$app/Contents/MacOS"
cp "$stage/Probe" "$app/Contents/MacOS/Reader"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>net.tagmat.copytaste.sandbox-test</string><key>CFBundleExecutable</key><string>Reader</string><key>CFBundleName</key><string>CopyTaste Sandbox Test</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$stage/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.files.user-selected.read-only</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements "$stage/entitlements.plist" "$app"
"$stage/Probe" "$app/Contents/MacOS/Reader"
