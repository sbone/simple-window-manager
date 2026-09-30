#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-debug}" in
    debug) build_args=(-c debug) ;;
    release) build_args=(-c release --arch arm64 --arch x86_64) ;;
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

swift build --product OptimalLayout "${build_args[@]}"
bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
app="Optimal Layout.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/OptimalLayout" "$app/Contents/MacOS/OptimalLayout"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "$signing_identity" "$app"
codesign --verify --strict "$app"
echo "Built $PWD/$app"
if [ "$signing_identity" = "-" ]; then
    echo "Ad-hoc signing: after code changes, remove and re-add this app in Accessibility settings."
fi
