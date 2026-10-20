#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build and publish the reviewed source and signed Sparkle update metadata.
command -v gh >/dev/null || { echo "Install GitHub CLI before publishing." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' before publishing." >&2; exit 1; }
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)
repository=${feed#https://github.com/}
repository=${repository%/releases/latest/download/appcast.xml}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
dmg="dist/Optimal-Layout-$version-$build.dmg"
test -s Resources/ReleaseNotes.md
test "$(gh repo view "$repository" --json isPrivate --jq .isPrivate)" = false
test -z "$(git status --porcelain)" || {
    echo "Commit the release changes before publishing." >&2
    exit 1
}
commit=$(git rev-parse HEAD)
test "$commit" = "$(git ls-remote origin refs/heads/main | cut -f1)" || {
    echo "Push this release commit to main before publishing." >&2
    exit 1
}
# A successful listing distinguishes an unused version from an API/auth failure.
tags=$(gh api --paginate "repos/$repository/releases" --jq '.[].tag_name')
if printf '%s\n' "$tags" | grep -Fxq "v$version"; then
    echo "Release v$version already exists. Choose an unused version." >&2
    exit 1
fi
bash scripts/release-macos.sh
test "$commit" = "$(git rev-parse HEAD)" && test -z "$(git status --porcelain)" || {
    echo "Source changed during the release build. Commit and restart publishing." >&2
    exit 1
}
(cd dist && shasum -a 256 -c "$(basename "$dmg").sha256")
bash scripts/check-dmg.sh "$dmg"
python3 scripts/check-appcast.py dist/appcast.xml "$dmg"
gh release create "v$version" --repo "$repository" \
    "$dmg" "$dmg.sha256" dist/appcast.xml \
    --target "$commit" --title "Optimal Layout $version" --notes-file Resources/ReleaseNotes.md --latest
