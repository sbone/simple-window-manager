#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dmg=${1:?Usage: bash scripts/check-dmg.sh /path/to/release.dmg}

hdiutil verify "$dmg" >/dev/null
codesign --verify --strict "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

mkdir -p .build
mountpoint=$(mktemp -d "$PWD/.build/dmg-check.XXXXXX")
trap 'hdiutil detach "$mountpoint" >/dev/null 2>&1; rmdir "$mountpoint"' EXIT
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$mountpoint" >/dev/null
app="$mountpoint/Optimal Layout.app"
test "$(readlink "$mountpoint/Applications")" = /Applications
test -s "$mountpoint/Read Me.txt"
test -s "$app/Contents/Resources/AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = com.stevenbone.optimallayout
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for executable in \
    "$app/Contents/MacOS/OptimalLayout" \
    "$sparkle/Sparkle" "$sparkle/Autoupdate" \
    "$sparkle/Updater.app/Contents/MacOS/Updater" \
    "$sparkle/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$sparkle/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
    lipo "$executable" -verify_arch arm64 x86_64
done
codesign --verify --deep --strict --all-architectures "$app"
test -s "$app/Contents/Resources/Sparkle-LICENSE.txt"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist")"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")"
otool -l "$app/Contents/MacOS/OptimalLayout" | grep -F '@executable_path/../Frameworks' >/dev/null
for architecture in arm64 x86_64; do
    signature=$(codesign -dv --verbose=4 --arch "$architecture" "$app" 2>&1)
    [[ "$signature" == *"Authority=Developer ID Application:"* ]]
    [[ "$signature" == *"(runtime)"* ]]
    [[ "$signature" == *"Timestamp="* ]]
done
spctl --assess --type execute --verbose=2 "$app"
status=0
output=$("$app/Contents/MacOS/OptimalLayout" --check-accessibility) || status=$?
case "$status:$output" in
    "0:Accessibility: allowed"|"1:Accessibility: denied") ;;
    *) echo "The packaged app failed its launch check: $output" >&2; exit 1 ;;
esac
echo "PASS: notarized DMG, packaged launch, Applications shortcut, icon, and both signed hardened-runtime architectures."
