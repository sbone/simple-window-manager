#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

notary_profile=${NOTARY_PROFILE:-}
if [ -z "$notary_profile" ] && [ -f .notary-profile ]; then
    notary_profile=$(cat .notary-profile)
fi
if [ -z "$notary_profile" ]; then
    echo "Set NOTARY_PROFILE or save an existing notarytool Keychain profile name in .notary-profile." >&2
    exit 1
fi
# Validate credentials before building; never read the password out of Keychain.
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null

swift test
sparkle_tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
public_key=$("$sparkle_tools/generate_keys" -p)
if [ "$public_key" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)" ]; then
    echo "The Sparkle signing key in Keychain does not match this app's public key." >&2
    exit 1
fi
bash scripts/build-app.sh release
app=".build/release-app/Optimal Layout.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
signing_identity=${CODE_SIGN_IDENTITY:-$(cat .codesign-identity)}
mkdir -p dist
stage=$(mktemp -d "$PWD/.build/distribution.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Optimal Layout.app"
ln -s /Applications "$stage/Applications"
cp Resources/Install.txt "$stage/Read Me.txt"
dmg="$PWD/dist/Optimal-Layout-$version-$build.dmg"
hdiutil create -volname "Optimal Layout $version" -srcfolder "$stage" -format UDZO -ov "$dmg"
codesign --force --sign "$signing_identity" --timestamp "$dmg"
codesign --verify --strict "$dmg"

# Keep Apple's response on failure so the submission ID is available for diagnosis.
submission="$dmg.notarization.json"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format json > "$submission"
if [ "$(plutil -extract status raw -o - "$submission")" != Accepted ]; then
    echo "Notarization was not accepted. See $submission and retrieve its log with notarytool log." >&2
    exit 1
fi
xcrun stapler staple "$dmg"
bash scripts/check-dmg.sh "$dmg"
(cd dist && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist")
release_url="${feed%/latest/download/appcast.xml}"
mkdir "$stage/updates"
cp "$dmg" "$stage/updates/"
cp Resources/ReleaseNotes.md "$stage/updates/$(basename "$dmg" .dmg).md"
"$sparkle_tools/generate_appcast" --maximum-versions 1 --maximum-deltas 0 \
    --download-url-prefix "$release_url/download/v$version/" \
    --link "$release_url/tag/v$version" --embed-release-notes \
    -o "$PWD/dist/appcast.xml" "$stage/updates"
python3 scripts/check-appcast.py dist/appcast.xml "$dmg"
echo "Ready to share: $dmg"
echo "Signed update feed: $PWD/dist/appcast.xml"
