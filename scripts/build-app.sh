#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

signing_args=(--force)
case "${1:-debug}" in
    debug) build_args=(-c debug); app="Optimal Layout.app" ;;
    release)
        build_args=(-c release --arch arm64 --arch x86_64)
        signing_args=(--force --options runtime --timestamp)
        app=".build/release-app/Optimal Layout.app"
        ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

signing_identity=${CODE_SIGN_IDENTITY:-}
if [ -z "$signing_identity" ] && [ -f .codesign-identity ]; then
    signing_identity=$(cat .codesign-identity)
fi
if [ -z "$signing_identity" ]; then
    echo "Choose a code-signing identity in .codesign-identity or CODE_SIGN_IDENTITY; see README.md." >&2
    echo "For an explicit ad-hoc build, use CODE_SIGN_IDENTITY=- (Accessibility may reset)." >&2
    exit 1
fi

if [ "${1:-debug}" = release ] && [ "$signing_identity" = "-" ]; then
    echo "Release builds require a Developer ID Application identity." >&2
    exit 1
fi

swift build --product OptimalLayout "${build_args[@]}"
bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/OptimalLayout" "$app/Contents/MacOS/OptimalLayout"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
sparkle_source=".build/artifacts/sparkle/Sparkle"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_source/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$sparkle"
cp "$sparkle_source/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
for component in \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle/Versions/B/Updater.app" \
    "$sparkle/Versions/B/Autoupdate" \
    "$sparkle"; do
    codesign "${signing_args[@]}" --sign "$signing_identity" \
        --preserve-metadata=identifier,entitlements "$component"
done
codesign "${signing_args[@]}" --sign "$signing_identity" "$app"
codesign --verify --deep --strict "$app"
if [ "${1:-debug}" = release ]; then
    lipo "$app/Contents/MacOS/OptimalLayout" -verify_arch arm64 x86_64
    signature=$(codesign -dv --verbose=4 "$app" 2>&1)
    if [[ "$signature" != *"Authority=Developer ID Application:"* ]]; then
        echo "Release builds must be signed with Developer ID Application." >&2
        exit 1
    fi
fi
echo "Built $PWD/$app"
if [ "$signing_identity" = "-" ]; then
    echo "Ad-hoc signing: after code changes, remove and re-add this app in Accessibility settings."
fi
