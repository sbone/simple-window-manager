# Simple Window Manager

A small, dependency-free AppKit menu-bar app, currently named **Optimal Layout**.
Targets macOS 14 or later. Swift Package Manager builds the executable; the
build script packages and locally signs the app.

## Requirements

- Full Xcode with a Swift 6 toolchain; verified with Xcode 26.3 / Swift 6.2.4
  on an Apple Silicon Mac running macOS 15.8.
- Xcode selected as the active developer directory. Check with
  `xcode-select -p` and `xcrun swift --version`. If needed, run
  `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
  and open Xcode once to finish its setup.
- No Homebrew packages or third-party dependencies are needed.

## Build and run

```sh
make run
```

This builds for the current Mac and opens `Optimal Layout.app` in the repo
root. Look for **OL** in the menu bar; there is no Dock icon or main window.
Quit the running app from that menu before rebuilding it.

On first launch, grant the app access in **System Settings → Privacy &
Security → Accessibility**. The **Enable Accessibility…** menu item can
request access again. If the app is missing from the list, use **+** to add
the generated app. Focus a normal resizable window before trying a shortcut.

| Shortcut | Action |
| --- | --- |
| ⌘⌥1 | Fill the display's usable area |
| ⌘⌥2 | Cycle left half → right half |
| ⌘⌥3 | Centered, full-height half-width window |
| ⌘⌥4 | Cycle upper-left → upper-right → lower-right → lower-left |
| ⌘⌥0 | Move to the next display |

Cycles are shared across windows and reset when the app restarts. Quit the
legacy Optimal Layout or other apps using these shortcuts before testing.

## Build commands

```sh
swift build    # Compile the native executable only
make build     # Package a native debug app without launching it
make release   # Package an optimized universal arm64 + x86_64 app
```

Both packaging commands write the same `Optimal Layout.app`. These builds
use ad-hoc signing for local development; distribution signing and
notarization are not configured. After a rebuild, macOS may require removing
and re-adding the app in Accessibility settings. Prefer the bundled app over
`swift run` so permissions apply to the app you will actually use.

## Manual smoke test

1. Launch the app and verify **OL** appears in the menu bar.
2. Grant Accessibility access, then focus a resizable TextEdit or Terminal window.
3. Try all four layout shortcuts, including repeated presses of 2 and 4.
   Check that placements avoid the menu bar and Dock; try a menu command too.
4. With two displays, try ⌘⌥0 in both directions. Current implementation
   preserves absolute window size and proportional position within usable bounds.
5. Quit from the menu and confirm the process exits.

On 2026-09-28, the user confirmed successful VS Code window adjustment on the
M4 MacBook Air. Complete layout cycles and the remaining smoke tests above
have not yet been confirmed.

Window behavior is still a prototype: multi-display geometry, Accessibility
errors, shortcut conflicts, and non-resizable/full-screen windows need runtime
validation. Preferences and launch at login are not implemented yet.

## Design and investigation

- [Reverse-engineering findings](optimal-layout-reverse-engineering.md)
- [Original investigation and handoff](optimal-layout-reverse-engineering-handoff.md)

The findings distinguish legacy behavior from replacement requirements.
The initial product keeps four built-in layouts and focused-window commands;
custom layouts and per-application rules are out of scope.
