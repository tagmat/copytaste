#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
stage=$(mktemp -d "${TMPDIR:-/tmp}/copytaste-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/CopyTaste.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
build_args=(-c release --disable-sandbox --cache-path "$PWD/.build/cache")
if [[ "${1:-}" == "--universal" ]]; then
    # One multi-arch build yields a universal binary under both the native and
    # the Swift Build engines; per-arch output folders exist only in the former.
    build_args+=(--arch arm64 --arch x86_64)
fi
if ! swift build -Xswiftc -warnings-as-errors "${build_args[@]}"; then
    if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == */CommandLineTools ]]; then
        echo "hint: the active developer directory is the Command Line Tools, which lack the SwiftUI macro plugin newer SDKs need." >&2
        echo "hint: install Xcode and run 'sudo xcode-select -s /Applications/Xcode.app', or prefix this script with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
    fi
    exit 1
fi
cp "$(swift build "${build_args[@]}" --show-bin-path)/CopyTaste" "$app/Contents/MacOS/CopyTaste"
if [[ "${1:-}" == "--universal" ]]; then
    for arch in arm64 x86_64; do lipo "$app/Contents/MacOS/CopyTaste" -verify_arch "$arch"; done
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -n "${COPYTASTE_SIGN_IDENTITY:-}" && "${COPYTASTE_SIGN_IDENTITY:-}" != "-" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :CopyTasteDataProtectionKeychain bool true' "$app/Contents/Info.plist"
fi
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
xattr -cr "$app"
codesign --force --sign "${COPYTASTE_SIGN_IDENTITY:--}" --options runtime "$app"
codesign --verify --deep --strict "$app"
mkdir -p dist
# Replace generated output as a unit: ditto otherwise keeps removed resources.
rm -rf "$PWD/dist/CopyTaste.app"
ditto --norsrc --noextattr "$app" "$PWD/dist/CopyTaste.app"
ditto -c -k --keepParent --norsrc --noextattr "$app" "$PWD/dist/CopyTaste-macOS.zip"
mkdir "$stage/verify"
ditto -x -k "$PWD/dist/CopyTaste-macOS.zip" "$stage/verify"
codesign --verify --deep --strict "$stage/verify/CopyTaste.app"
test -x "$stage/verify/CopyTaste.app/Contents/MacOS/CopyTaste"
if [[ -n "${COPYTASTE_SIGN_IDENTITY:-}" ]]; then
    echo "Built and signed: $PWD/dist/CopyTaste-macOS.zip"
else
    echo "Built with a local ad-hoc signature: $PWD/dist/CopyTaste-macOS.zip"
fi
