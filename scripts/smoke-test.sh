#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
if ! mkdir .build/smoke-test.lock 2>/dev/null; then
    echo "A smoke test is already running (or .build/smoke-test.lock is stale)." >&2
    exit 1
fi
restore() {
    osascript -e 'if application id "local.OptimalLayout.SmokeTest" is running then tell application id "local.OptimalLayout.SmokeTest" to quit' >/dev/null 2>&1 || true
    # Give a cancelled helper time to finish its own window/hotkey cleanup.
    for attempt in {1..100}; do
        if ! pgrep -x OLSmokeTest >/dev/null; then break; fi
        sleep 0.1
    done
    osascript -e 'tell application id "com.stevenbone.optimallayout" to quit' >/dev/null 2>&1 || true
    open "$PWD/Optimal Layout.app" || true
    rmdir .build/smoke-test.lock
}
trap restore EXIT
trap 'exit 130' INT TERM
if [ -d "Optimal Layout.app" ]; then
    osascript -e 'tell application id "com.stevenbone.optimallayout" to quit'
fi
bash scripts/build-app.sh
swift build --product OLSmokeTest
bin_dir=$(swift build --show-bin-path)
helper="$PWD/.build/OL Smoke Test.app"
mkdir -p "$helper/Contents/MacOS"
cp "$bin_dir/OLSmokeTest" "$helper/Contents/MacOS/OLSmokeTest"
cp Resources/SmokeTest-Info.plist "$helper/Contents/Info.plist"
signing_identity=${CODE_SIGN_IDENTITY:-$(cat .codesign-identity)}
codesign --force --sign "$signing_identity" "$helper"
codesign --verify --strict "$helper"
make check-accessibility
> .build/smoke-test.log
echo "The test uses its own windows. Leave the keyboard and mouse idle until it finishes."
open -n -W "$helper" --stdout "$PWD/.build/smoke-test.log" --stderr "$PWD/.build/smoke-test-stderr.log" --args "$PWD/Optimal Layout.app" "$@"
cat .build/smoke-test.log
grep -qx 'RESULT PASS' .build/smoke-test.log
