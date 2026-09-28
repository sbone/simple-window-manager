#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-debug}" in
    debug) build_args=(-c debug) ;;
    release) build_args=(-c release --arch arm64 --arch x86_64) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

swift build "${build_args[@]}"
bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
app="Optimal Layout.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/OptimalLayout" "$app/Contents/MacOS/OptimalLayout"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
echo "Built $PWD/$app"
