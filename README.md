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
Security → Accessibility**. The **Accessibility Settings…** menu item opens
that pane and requests access again. If the app is missing from the list, use **+** to add
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
default to ad-hoc signing for local development; distribution signing and
notarization are not configured. After code changes, the app's signing
requirement changes and the previous Accessibility grant can stop matching.
Prefer the bundled app over
`swift run` so permissions apply to the app you will actually use.

### Commands stop working after a rebuild

This was reproduced on 2026-09-28: both shortcuts and menu commands stopped
after `make run`, and macOS logged `Failed to match existing code requirement`
for `local.OptimalLayout` and `kTCCServiceAccessibility`.

1. Quit OL.
2. In System Settings → Privacy & Security → Accessibility, remove the old
   **Optimal Layout** entry, even if it appears enabled.
3. Use **+** to add `Optimal Layout.app` from this repo and enable it.
4. Reopen that app without rebuilding: `open "Optimal Layout.app"`.

The user confirmed on 2026-09-28 that resetting Accessibility access restored
window control after this rebuild failure.

Window commands now check Accessibility trust and explain how to recover if
permission is missing. The OS permission grant still requires user action.

To avoid changing the app's signing identity on each rebuild, use an existing
code-signing certificate from your keychain:

```sh
security find-identity -v -p codesigning
CODE_SIGN_IDENTITY="<identity name or hash from the command above>" make run
```

Use the same identity for subsequent builds (for example, export
`CODE_SIGN_IDENTITY` in your development shell). Grant Accessibility once
after switching identity. The build fails if the requested identity cannot be
used; it does not silently fall back to ad-hoc signing. Certificate setup is
not automated.

## Automated tests

```sh
make test      # Or: swift test
```

Nine tests use Swift Testing (included with the toolchain), with no added
dependencies or Accessibility permission. They exercise the same geometry code
used by the app without launching it or moving any real windows:

- Full and centered layouts within usable bounds, including offset displays.
- Half and quadrant cycle order, wrapping, independent state, and session reset.
- Fractional window sizes staying inside usable bounds.
- Transfer between different display sizes, preserving absolute size and relative origin.
- AX/AppKit coordinate conversion with a display above the primary display.
- Selecting the display containing the largest portion of a spanning window,
  including ties, off-screen windows, and empty display lists.

These tests reproduced and now guard against two bugs: a vertically stacked
display shifting the coordinate origin, and a spanning window selecting the
first intersecting display instead of the largest overlap.

### Next automation layer

Geometry tests cannot prove that another app accepts a window resize or that
macOS delivers a shortcut. An opt-in GUI integration harness is the next step;
it is not implemented yet. It should create its own resizable test window,
focus it, send each shortcut (and activate each menu item through Accessibility),
then poll the actual window frame with a deadline and a small point tolerance.
It should close its own window when finished. Restart OL to establish known
cycle state before each complete run.

| Behavior | Programmatic check still needed |
| --- | --- |
| Shortcuts and menu actions | Drive the running app and compare actual window frames with expected placements. |
| Switch Display | Use connected displays, check transfer in both directions and wraparound; skip explicitly if only one display is connected. |
| Shortcut conflicts | Reserve a shortcut before launching OL and check that OL reports the registration failure; reporting is not implemented yet. |
| Accessibility failures | Test permission-denied and rejected-resize results once error reporting exists, plus an opt-in check with real macOS permissions. |
| Launch at login | After implementation, verify registration state and separately verify launch in a fresh login session. |

The GUI harness will need a logged-in macOS desktop and Accessibility permission
for both OL and the helper. Permission grants remain a user action. Synthetic
display rectangles cover geometry today; they do not replace a real multi-display
integration run.

## Manual smoke test

1. Launch the app and verify **OL** appears in the menu bar.
2. Grant Accessibility access, then focus a resizable TextEdit or Terminal window.
3. Try all four layout shortcuts, including repeated presses of 2 and 4.
   Check that placements avoid the menu bar and Dock; try a menu command too.
4. With two displays, try ⌘⌥0 in both directions. Current implementation
   preserves absolute window size and proportional position within usable bounds.
5. Quit from the menu and confirm the process exits.

On 2026-09-28, the user confirmed successful VS Code window adjustment on the
M4 MacBook Air. Cycle calculations now have automated coverage; complete
shortcut delivery and the remaining GUI smoke tests above have not yet been confirmed.

Window behavior is still a prototype: multi-display geometry, Accessibility
errors, shortcut conflicts, and non-resizable/full-screen windows need runtime
validation. Preferences and launch at login are not implemented yet.

## Design and investigation

- [Reverse-engineering findings](optimal-layout-reverse-engineering.md)
- [Original investigation and handoff](optimal-layout-reverse-engineering-handoff.md)

The findings distinguish legacy behavior from replacement requirements.
The initial product keeps four built-in layouts and focused-window commands;
custom layouts and per-application rules are out of scope.
