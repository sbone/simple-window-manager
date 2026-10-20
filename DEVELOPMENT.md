# Development

Build, test, and release instructions. For installation and usage, see
[README.md](README.md).

## Setup

Building from source requires full Xcode with a Swift 6 toolchain.
Select Xcode as the active developer directory and complete its first-launch
setup. Check with `xcode-select -p` and `xcrun swift --version`; if needed, run
`sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.
No Homebrew packages are needed. Swift Package Manager downloads Sparkle for updates.

Choose an existing code-signing identity once per Mac:

```sh
security find-identity -v -p codesigning
printf '%s\n' '<identity name or hash>' > .codesign-identity
make run
```

`.codesign-identity` is git-ignored; the private key stays in Keychain.
`CODE_SIGN_IDENTITY` overrides the file. Missing or unusable signing configuration
fails the build. For an explicit ad-hoc build, use `CODE_SIGN_IDENTITY=- make build`,
but Accessibility access may reset after code changes.

`make run` builds and opens `Optimal Layout.app` in the repo root. Look for the **window-grid icon**
in the menu bar; there is no Dock icon or main window. Quit OL before rebuilding.
Prefer the bundled app over `swift run` so permissions apply to the app you use.

On first launch, grant access in **System Settings → Privacy & Security →
Accessibility**. The **Accessibility Settings…** menu item opens that pane.
If OL is missing, use **+** to add the generated app.

Keep the signing identity and bundle identifier stable to preserve permission.
Use `make check-accessibility` before and after rebuilding: it checks the existing
bundle without prompting or moving windows, writes `.build/accessibility-check.log`,
and fails if access is denied. See [recovery steps](README.md#accessibility-troubleshooting).

## Build and test

| Command | Purpose |
| --- | --- |
| `make run` | Build and open the app |
| `make build` | Package and sign a native debug app |
| `make release` | Package and sign a universal arm64 + x86_64 release |
| `make dist` | Test, build, notarize, and create a distributable DMG |
| `make publish` | Test, build, notarize, and publish a GitHub release and Sparkle feed |
| `swift build` | Compile the executable only |
| `make check-accessibility` | Check the existing bundle's Accessibility grant |
| `make test` | Run Swift and publishing tests without Accessibility permission |
| `make smoke-test` | Run GUI checks on a logged-in desktop |

Debug builds write `Optimal Layout.app`; universal releases write
`.build/release-app/Optimal Layout.app`. Release builds require a Developer ID
Application certificate and enable hardened runtime with a secure timestamp.

### Create a distributable DMG

Use the signing setup above and an existing `notarytool` Keychain profile:

```sh
printf '%s\n' '<Keychain profile name>' > .notary-profile
make dist
```

`NOTARY_PROFILE` overrides the git-ignored profile-name file. On this Mac, the
existing `MakeStem Notary` profile is reused; credentials stay in Keychain. For a
new Mac, use `xcrun notarytool store-credentials` to create a profile interactively.
Sparkle's existing signing key must also be present in Keychain; `make dist`
checks that its public key matches `SUPublicEDKey` before building the app.

The script runs Swift and publishing tests, builds both architectures, signs the app and DMG,
submits the DMG to Apple, staples its accepted ticket, and checks Gatekeeper.
Share `dist/Optimal-Layout-VERSION-BUILD.dmg`; its `.sha256` file is also generated.
The image contains the app, an Applications shortcut, and installation instructions.
An ordinary first-open confirmation for downloaded software is expected.
The final check mounts the DMG read-only and verifies the contents, both signed
architectures, and Gatekeeper acceptance of the app. Rerun it independently with
`bash scripts/check-dmg.sh dist/Optimal-Layout-VERSION-BUILD.dmg`.

Increment `CFBundleVersion` in `Resources/Info.plist` for each shared build.
The installer instructions receive the version and build from the packaged app.
Distribution follows Apple's
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
Sparkle verifies signed updates before installing them. Use **Automatically Check
for Updates** in the menu to control background checks; installation uses Sparkle’s
standard confirmation UI.

`make dist` also creates and verifies `dist/appcast.xml`, signed with the same
Sparkle Keychain key used by Makestem. Before publishing, update both version
fields and `Resources/ReleaseNotes.md`, then commit and
push the reviewed source to `main`. Install GitHub CLI and authenticate with
`gh auth login`. Run `make publish` to check authentication, repository visibility,
and version availability before rebuilding and notarizing the installer. It uploads
the fresh DMG, checksum, and feed as a release targeting that exact commit, and
stops if the source changes during the build. The repository
must remain public so installed apps can fetch updates without authentication.
The release builder verifies the archive and feed; publishing also checks the
checksum and refuses to replace an existing version. Builds before 0.2.0 need
one manual installation to gain Sparkle.

The Swift unit tests cover window geometry, display selection, layout cycles,
Accessibility failures, shortcut registration, and settings diagnostics.
`make test` also runs the Python publishing workflow checks. They do not move real windows
or register real shortcuts.

The GUI suite builds `.build/OL Smoke Test.app`, which needs its own Accessibility
grant alongside OL's. Grant it on first run, then rerun. **Leave the keyboard and
mouse idle during the test.** It uses disposable windows; click **Stop Test** or
close the test window to cancel. Checks cover layouts, shortcuts, menu commands,
error feedback, and display switching (skipped with one display).

To include login-item registration and persistence checks:

```sh
bash scripts/smoke-test.sh --login-item
```

This changes the real login setting and restores it afterward; a force-killed
run may require manual restoration. Resolve pending macOS approval first.
Actual startup after login remains a manual check.

Logs are in `.build/smoke-test.log` and `.build/smoke-test-stderr.log`.
Failures, cancellation, or missing permissions return a nonzero status. The
harness cleans up and restarts OL afterward. After a force-kill, remove a stale
`.build/smoke-test.lock` only after confirming no helper is running.

## App icon assets

The [1024px master](Resources/AppIcon.png) and [macOS iconset](Resources/AppIcon.iconset/)
produce the bundled `Resources/AppIcon.icns`. To repack the existing sizes:

```sh
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## Verification record

Dated results describe the build tested at that time. Outstanding checks:
fresh installation on another Mac, native Intel execution, a real Sparkle
upgrade, startup after logout/login, pending login approval, and registration
errors. Settings now presents login errors instead of a separate error dialog.

**2026-10-20:** `make test` passed 26 Swift tests and seven publishing checks.
The user reports continued successful use on an M4 Air. No GUI suite or
notarization was run for this cleanup.

**GUI verified, 2026-09-28:** 24 unit tests and 31 GUI checks passed on an M4
MacBook Air with two displays, including login-item restoration. Universal builds
and Accessibility retention across certificate-signed rebuilds also passed.
Toolchain: Xcode 26.3 / Swift 6.2.4 on macOS 15.8.

**Release verified, 2026-09-30:** version 0.2.0 (build 3) passed all 24 unit tests,
universal architecture and hardened-runtime signature checks, Apple notarization,
ticket validation, Gatekeeper assessment, and a packaged launch check. Sparkle's
helpers contain both architectures; the update archive's Ed25519 signature and
feed metadata also pass verification. Both app architectures target macOS 14.
First installation on another Mac, native Intel execution, and installing a future
Sparkle update remain tester checks; the GUI suite was not rerun for this release.
