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

## Configure signing once per Mac

Choose an existing code-signing identity from your keychain and save its name
or hash in the local configuration file:

```sh
security find-identity -v -p codesigning
printf '%s\n' '<identity name or hash from the command above>' > .codesign-identity
```

`.codesign-identity` is git-ignored and stores only the identity reference; the
private key stays in Keychain. This M4 Air is configured to use the existing
**Developer ID Application: Quality Time Studio LLC** certificate. Ordinary
`make build`, `make run`, and `make release` now use that same identity.

`CODE_SIGN_IDENTITY` overrides the file when set. Missing configuration or an
unusable identity causes the build to fail; there is no silent ad-hoc fallback.
For a deliberately ad-hoc build, use `CODE_SIGN_IDENTITY=- make build`, knowing
that code changes can invalidate Accessibility access. Certificate creation is
not automated.

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

## Failure feedback

When a window command fails, OL beeps and changes its menu-bar label to **OL!**.
Open **Window Command Failed…** in the menu for the reason and recovery advice;
the same details appear in the menu-bar tooltip. Feedback covers no active app
or focused window, invalid window data, unavailable displays, a single-display
Switch Display attempt, unsupported movement/resizing, and Accessibility API
failures. If moving succeeds but resizing fails, the message says the window
was partially changed. A failed layout does not advance its half/quadrant cycle.

Shortcut registration requests exclusive Carbon hotkeys. When macOS reports a
conflict or registration error, **OL! → Shortcut Problems…** identifies the
exact shortcut. Other shortcuts continue registering, and menu commands remain
available. Resolve the conflict and restart OL to retry registration. Exclusive
registration detects conflicts reported by Carbon; it cannot detect every
third-party event tap or shortcut interception mechanism.

A successful window command clears the last window error. Shortcut problems
remain visible until a restart registers them successfully. Window errors do
not open dialogs or steal focus automatically; details open only when requested.
The existing Accessibility-permission dialog still offers **Open Settings**.

## Build commands

```sh
swift build    # Compile the native executable only
make build     # Package a native debug app without launching it
make release   # Package an optimized universal arm64 + x86_64 app
make check-accessibility # Check the packaged app's actual Accessibility grant
```

Both packaging commands write the same `Optimal Layout.app`, signed with the
configured identity. Notarization and a distribution pipeline are not configured.
Prefer the bundled app over `swift run` so permissions apply to the app you
will actually use.

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

### Verify permission survives a rebuild

Switching from the old ad-hoc build to certificate signing requires one final
Accessibility grant using the recovery steps above. Thereafter, keep using the
same certificate and bundle identifier. macOS uses the app's designated
requirement to recognize updated builds; see Apple's
[code-signing requirements explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

```sh
make check-accessibility   # Must report Accessibility: allowed
# Quit OL from the menu before replacing the app.
make release               # Changes native debug into universal release
make check-accessibility   # Should still report Accessibility: allowed
open "Optimal Layout.app"
```

The check launches a separate, short-lived instance through Launch Services,
calls `AXIsProcessTrusted()`, and exits without registering shortcuts, opening
menus, prompting for access, or moving windows. Its result is printed and saved
in `.build/accessibility-check.log`; `make` returns a failure if access is denied.
It checks the existing bundle without rebuilding it.

**Verified on the M4 Air, 2026-09-28:** after granting access to the
certificate-signed native debug app, switching to a universal release retained
Accessibility access without another grant. The two binaries had different
code hashes and identical designated requirements. Strict signature validation
passed for the rebuilt app.

## Automated tests

```sh
make test      # Or: swift test
```

Twenty-four tests use Swift Testing (included with the toolchain), with no added
dependencies or Accessibility permission. Nine exercise the same geometry code
used by the app; fifteen cover failures using injected Accessibility/Carbon
results. They do not launch the app, move real windows, or register real shortcuts:

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

Failure coverage includes absent or malformed focused windows, denied or failed
Accessibility queries, invalid frames, non-settable sizes checked before moving,
failed position writes stopping resize, partial move/resize failures, correct AX
value writes, cycle preservation on failure, exclusive shortcut registration,
continuing after one shortcut conflicts, unexpected registration failures, and
retaining shortcut warnings after successful window commands.

**Runtime validation — 2026-09-28:** a separate temporary probe attempted all
five exclusive shortcuts while the signed app was running. Carbon returned
`eventHotKeyExistsErr` (`-9878`) for each, and the production registration code
reported the correct combination. The probe sent no keystrokes or window
commands. The signed universal build passed verification and retained
Accessibility access. The GUI harness below now also checks warning presentation.

### GUI smoke test

```sh
make smoke-test
```

This opt-in test requires a logged-in macOS desktop, Swift 6.2+, and the stable
signing configuration above. It builds the main app and a separate signed helper
at `.build/OL Smoke Test.app`. On first run, grant **OL Smoke Test** Accessibility
access in System Settings, then rerun the command. OL also needs its existing
grant. Missing permission reports `BLOCKED` and a nonzero command exit; the test
does not grant permissions automatically.

The helper creates its own disposable window and temporarily takes focus.
**Leave the keyboard and mouse idle while it runs.** Click **Stop Test** or close
the test window to cancel. The helper checks focus before sending shortcuts or
selecting menu commands. Existing user document windows are not test fixtures.

The run covers:

- Full, centered, left/right, and clockwise quadrant placements through both
  real keyboard events and Accessibility-driven menu clicks, including wraparound.
- A non-resizable window: no partial movement, the `OL!` indicator, the failure
  menu entry, dialog text/dismissal, retry staying at the first half, and warning clearance.
- A deliberately reserved ⌘⌥2 shortcut: the conflict indicator and exact dialog
  text, other shortcuts still working, the corresponding menu action still working,
  warnings surviving successful commands, and a clean restart after releasing the shortcut.
- With multiple connected displays, next-display movement through shortcuts and
  menu actions with wraparound, preserving size and relative position. A one-display
  setup prints an explicit `SKIP` for this portion.

Expected rectangles are calculated from the product specification independently
of production geometry. The helper observes its real `NSWindow.frame`, allows
2 points of rounding tolerance, and requires three matching samples. It polls
conditions with four-second deadlines instead of assuming success after a fixed
delay. Cross-process Accessibility work runs off the main actor so the helper
can continue serving OL's window queries and writes.

Results are saved to `.build/smoke-test.log`; failures include expected/actual
frames or an explanation plus a bounded Accessibility snapshot of OL. Helper
stderr goes to `.build/smoke-test-stderr.log`. The command returns nonzero for
failure, cancellation, or missing permission. It releases the helper's temporary
shortcut, closes its windows, and restarts one normal OL instance after the run.
A lock prevents overlapping runs; after a force-kill, remove a stale
`.build/smoke-test.lock` directory only after confirming no helper is running.

**Verified on 2026-09-28:** 27 GUI checks passed on the M4 Air; multi-display
placement was explicitly skipped because macOS exposed one display. The helper's
first run also correctly reported missing permission and restored OL. These
checks cover the controlled AppKit test window, not every application's sizing
constraints or every display arrangement.

## Manual smoke test

1. Launch the app and verify **OL** appears in the menu bar.
2. Grant Accessibility access, then focus a resizable TextEdit or Terminal window.
3. Try all four layout shortcuts, including repeated presses of 2 and 4.
   Check that placements avoid the menu bar and Dock; try a menu command too.
4. With two displays, try ⌘⌥0 in both directions. Current implementation
   preserves absolute window size and proportional position within usable bounds.
5. Quit from the menu and confirm the process exits.

On 2026-09-28, the user confirmed successful VS Code window adjustment on the
M4 MacBook Air. Cycle calculations now have automated coverage; shortcut and menu delivery plus warning presentation now pass the automated GUI
harness. Physical multi-display behavior and other applications' edge cases remain.

Window behavior is still a prototype: physical multi-display behavior and
third-party/full-screen window constraints still need validation. The app checks API results but does not yet read the resulting frame
back: an app can report success while constraining the requested size. Preferences
and launch at login are not implemented yet.

## Design and investigation

- [Reverse-engineering findings](optimal-layout-reverse-engineering.md)
- [Original investigation and handoff](optimal-layout-reverse-engineering-handoff.md)

The findings distinguish legacy behavior from replacement requirements.
The initial product keeps four built-in layouts and focused-window commands;
custom layouts and per-application rules are out of scope.
