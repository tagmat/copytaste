#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
stage=$(mktemp -d "${TMPDIR:-/tmp}/copytaste-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/CopyTaste.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache"
    swift build -c release --arch x86_64 --disable-sandbox --cache-path "$PWD/.build/cache"
    lipo -create .build/arm64-apple-macosx/release/CopyTaste .build/x86_64-apple-macosx/release/CopyTaste -output "$app/Contents/MacOS/CopyTaste"
else
    swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache"
    cp .build/release/CopyTaste "$app/Contents/MacOS/CopyTaste"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
xattr -cr "$app"
codesign --force --deep --sign "${COPYTASTE_SIGN_IDENTITY:--}" --options runtime "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
ditto --norsrc --noextattr "$app" "$PWD/dist/CopyTaste.app"
ditto -c -k --keepParent --norsrc --noextattr "$app" "$PWD/dist/CopyTaste-macOS.zip"
if [[ -n "${COPYTASTE_SIGN_IDENTITY:-}" ]]; then
    echo "Built and signed: $PWD/dist/CopyTaste-macOS.zip"
else
    echo "Built with a local ad-hoc signature: $PWD/dist/CopyTaste-macOS.zip"
fi
