#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Publish the reviewed installer and signed Sparkle update metadata.
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' Resources/Info.plist)
repository=${feed#https://github.com/}
repository=${repository%/releases/latest/download/appcast.xml}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
dmg="dist/Optimal-Layout-$version-$build.dmg"
test -s "$dmg"
test -s "$dmg.sha256"
test -s dist/appcast.xml
test -s Resources/ReleaseNotes.md
test "$(gh repo view "$repository" --json isPrivate --jq .isPrivate)" = false
test -z "$(git status --porcelain --untracked-files=no)" || {
    echo "Commit the release changes before publishing." >&2
    exit 1
}
commit=$(git rev-parse HEAD)
test "$commit" = "$(git ls-remote origin refs/heads/main | cut -f1)" || {
    echo "Push this release commit to main before publishing." >&2
    exit 1
}
(cd dist && shasum -a 256 -c "$(basename "$dmg").sha256")
bash scripts/check-dmg.sh "$dmg"
python3 scripts/check-appcast.py dist/appcast.xml "$dmg"
gh release create "v$version" --repo "$repository" \
    "$dmg" "$dmg.sha256" dist/appcast.xml \
    --target "$commit" --title "Optimal Layout $version" --notes-file Resources/ReleaseNotes.md --latest
