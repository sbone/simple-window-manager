# Optimal Layout 2.3.2 Reverse Engineering

This is the working findings report for the clean-room replacement. Conclusions are labeled by evidence level.

## Executive Summary

The legacy app is a much broader window-management utility than the intended replacement needs to be. Its core behavior is small and well defined: register global shortcuts, find the focused Accessibility window, convert a saved percentage rectangle into a screen frame, and set the window's Accessibility position and size.

The replacement should initially target only:

- a menu-bar app;
- four built-in layout commands exposed in the menu;
- global shortcut registration;
- focused-window move and resize;
- switch to the next display;
- Accessibility permission onboarding;
- launch at login if needed.

The four layouts are product-defined commands. Users do not create custom window shapes or sizes, and there is no per-application layout assignment. Every command is available to every eligible focused application window.

Product-specific behavior for the fourth command: `⌘⌥4` is a stateful quadrant cycle. Its first press places the focused window in the upper-left quadrant, then subsequent presses move it to the upper-right, lower-right, lower-left, and back to upper-left. The first press therefore establishes the cycle at upper-left rather than preserving a prior quadrant.

Product-specific behavior for the second command: `⌘⌥2` is a stateful half-screen cycle. Its first press places the focused window in the left half, the next press moves it to the right half, and subsequent presses alternate between right and left. The first press establishes the cycle at the left half.

Window browsing, window lists, tabs, grid navigation, incremental movement, incremental resizing, crash reporting, mailing-list signup, Growl feedback, TotalFinder support, and Sparkle updates are legacy behavior. They remain useful reference points, but are outside the initial product scope.

## Binary / Architecture

**Confirmed by binary/static inspection:**

- Bundle: `net.lowndes.windowflow`
- Version: `2.3.2` / build `870`
- Executable: `Optimal Layout`
- Binary architecture: `x86_64` only
- Minimum system version: macOS 10.7
- `LSUIElement` is enabled, so the app is an agent/menu-bar application.
- The binary was built with an old macOS 10.9 SDK/toolchain.

The replacement must be built as a universal binary for `arm64` and `x86_64`, with macOS 14 as its minimum target.

## Frameworks and Dependencies

**Confirmed by binary/static inspection:** the app links AppKit/Cocoa, Carbon, ApplicationServices, Quartz, CoreServices, ScriptingBridge, SystemConfiguration, AddressBook, OSAKit, Security, IOKit, and Sparkle.

The dependencies relevant to the replacement are:

- ApplicationServices for Accessibility APIs;
- AppKit for `NSScreen`, the menu-bar app, preferences, and workspace state;
- Carbon for the legacy global hotkey implementation.

Sparkle, AddressBook, OSAKit, ScriptingBridge, and the other legacy integrations are not requirements for the MVP.

## Global Shortcut Implementation

**Confirmed by binary/static inspection:** the app uses Carbon global hotkeys. The binary imports `RegisterEventHotKey`, `UnregisterEventHotKey`, `InstallEventHandler`, and `GetEventParameter`. It contains `HotKeyController`, `SGHotKeyCenter`, `SGHotKey`, `HotKeyArray`, and methods named `registerHotKey`, `unregisterHotKey`, `processCarbonEvent`, and `hotKeyWithIdentifier:`.

It also contains an event-tap path (`setEventTapHotkeys`, `checkForEventTapHotkey`) and local ShortcutRecorder controls. This suggests separate handling for global shortcuts, local shortcuts, and possibly shortcuts that cannot be registered through Carbon. The exact fallback rules remain unverified.

The default position records store:

```text
keyboardShortcut = { keyCode, modifiers }
isGlobalShortcut = true/false
displayButtonInOL = true/false
displayButtonInMenuBar = true/false
```

## Window Manipulation Implementation

**Confirmed by binary/static inspection:** the app uses public Accessibility APIs. It imports `AXIsProcessTrusted`, `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`, `AXUIElementPerformAction`, and related functions.

The relevant implementation symbols include:

- `AccessibilityWindowsOperation`
- `ApplySavedPosition`
- `WindowActionController`
- `PositionWindow`
- `windowFrameFromPercent:onScreen:`
- `windowFrameInScreenPercent`
- `applyWindowPositionFromHotkey:`

The likely modern core is therefore directly supported by macOS public APIs: obtain the focused window, read its frame, calculate a target frame, then set `kAXPositionAttribute` and `kAXSizeAttribute`. Exact error handling and ordering of the position/size writes still require runtime or disassembly verification.

## Position / Layout Data Model

**Confirmed by bundled defaults:** positions are stored in an ordered `windowPositions` array. A custom layout contains a `RectString` with four percentage values:

```text
x,y,width,height
```

Observed defaults include:

```text
0,0,100,100
0,0,50,100
25,0,50,100
50,0,50,50
```

This confirms the product hypothesis that layouts are proportional rather than fixed pixel rectangles. The names and flags are also persisted with each layout. A separate `type` value is present for Undo Position, while Switch Display is identified by its name and zero rectangle in the defaults.

**Confirmed by static symbols:** the app has `windowFrameFromPercent:onScreen:` and `windowFrameInScreenPercent`, plus `ScreenGridView.screenRectToPercentRect:`. The position editor is therefore based on percentage conversion.

The legacy app uses editable percentage rectangles, but this is not a replacement requirement. The replacement should keep its four geometries as built-in product constants. It should define the coordinate origin and whether geometry uses `visibleFrame` explicitly; that detail is still pending verification.

## Multi-Display Behavior

**Confirmed by static inspection:** the app has `PositionWindow.nextScreen`, `PositionWindow.moveWindowToOtherDisplay`, `getWindowScreen`, `getScreenOrigin`, screen setup/change handlers, and Cocoa/Carbon screen-coordinate conversion helpers.

**Unknown:** whether Switch Display preserves absolute size, proportional size, relative position, or some combination. This is the most valuable remaining runtime test.

The MVP should choose and document one deterministic rule. The best initial candidate is to preserve the window's current relative rectangle and apply it to the next display's usable frame.

## Ignored Window Behavior

**Confirmed by static inspection:** the app has separate collections and methods for ignored applications, tabs, and windows, including `appsToIgnore`, `appTabsToIgnore`, `windowsToIgnore`, `isIgnoredApp`, `isIgnoredAppTab`, `isIgnoredWindow`, `ignoreApp`, `ignoreAppTabs`, and `ignoreWindow`.

Ignored-window configuration is excluded from the replacement. Every layout command should work with every eligible focused application window.

## Preference Storage

**Confirmed by bundled resources:** defaults are stored as standard property-list data. The bundled `OL-Defaults.plist` contains window positions, shortcut dictionaries, menu visibility flags, grid settings, animation/HUD-related settings, and many legacy window-browser preferences.

The replacement should persist only shortcut settings and basic app preferences, using `UserDefaults` with Codable data if needed. It should not persist user-defined layouts, app-to-layout assignments, legacy key names, or unrelated defaults.

## UI / Overlay Behavior

**Confirmed by resources and symbols:** the legacy app includes Preferences nibs, a switcher/window browser, screen-grid previews, position buttons, images for HUD/menu feedback, and Growl status reporting.

These are not part of the initial replacement target. A simple menu-bar menu and optional transient confirmation are sufficient until keyboard behavior is stable.

## Legacy / Obsolete APIs

The app's Carbon hotkey implementation is legacy but still useful as behavioral evidence. The replacement should evaluate a maintained global-hotkey approach compatible with macOS 14 before copying the mechanism.

Sparkle 1.x, Growl-style notifications, AddressBook signup, TotalFinder compatibility, and old crash reporter resources should be excluded from the MVP.

## Behavior That Can Be Reimplemented with Public APIs

- Accessibility trust check and focused-window lookup.
- Window frame reads and writes through `AXUIElement`.
- Screen selection through `NSScreen`.
- Built-in layout conversion.
- Menu-bar UI and preferences.
- Launch-at-login using the modern ServiceManagement API.

## Behavior That Requires Runtime Verification

1. Whether layout coordinates use `visibleFrame` or full screen bounds.
2. The exact Switch Display geometry rule.
3. Whether applying a layout writes position before size or size before position.
4. Animation and confirmation behavior.
5. Behavior for non-resizable, minimized, full-screen, and utility windows.
6. The shortcut fallback path and conflict behavior.

## Proposed Modern Architecture

- Swift and AppKit, macOS 14 minimum.
- Menu-bar application with a small Preferences window.
- `AXUIElement` service for focused-window access and frame changes.
- `NSScreen.visibleFrame` as the initial usable-screen basis.
- Codable configuration persisted through `UserDefaults`.
- One shortcut service with explicit conflict/error reporting.
- Separate `WindowAction.layout` and `WindowAction.switchDisplay` actions.

## Suggested MVP

The first implementation should contain only:

1. Accessibility onboarding.
2. Four built-in layout commands shown in the menu.
3. Global shortcuts for those layouts.
4. Focused-window move and resize.
5. Switch to the next display.
6. A minimal menu-bar menu and preferences window.
7. Universal `arm64`/`x86_64` build.

The initial vertical slice and all four built-in commands are implemented. The next step is to validate complete layout cycles, menu commands, and one- and two-display behavior, then address window-control errors and shortcut conflicts before adding preferences.

## Implementation Progress

**Started:** a dependency-free Swift package now exists in `Package.swift` and `Sources/OptimalLayout/main.swift`.

The first slice includes:

- an accessory/menu-bar application entry point;
- four built-in layout actions;
- the `⌘⌥2` left/right cycle;
- the `⌘⌥4` upper-left → upper-right → lower-right → lower-left cycle;
- Carbon global hotkey registration for `⌘⌥1` through `⌘⌥4` and `⌘⌥0`;
- focused-window lookup through Accessibility;
- frame updates through Accessibility position and size attributes;
- next-display movement preserving the current relative position.

**Confirmed by build validation — 2026-09-28, M4 MacBook Air:** native debug and universal release builds now pass with Xcode 26.3, Swift 6.2.4, and the macOS 26.2 SDK on macOS 15.8. The former toolchain blocker no longer reproduces. Sandboxed builds still require access to Swift's user cache directories.

`make build` packages a native debug app; `make release` packages an optimized universal app. Both produce an ad-hoc-signed `Optimal Layout.app` with a separate development bundle identifier, `local.OptimalLayout`. Binary inspection confirms both `arm64` and `x86_64` slices target macOS 14.0, and strict code-signature verification passes. The app now requests Accessibility access at launch and from its menu. See [README.md](README.md) for setup and a manual smoke test.

**Confirmed by runtime behavior — user-reported, 2026-09-28:** the replacement app successfully adjusts a VS Code window on the M4 MacBook Air. This validates the initial window-control path in a real application. The report does not specify which commands were exercised, so complete cycle order, menu-bar/Dock clearance, other applications, and multi-display behavior remain unverified.

The current Switch Display prototype preserves absolute size and proportional position; this differs from the proportional-size candidate above and does not establish the legacy app's behavior. Preferences, launch at login, and distribution notarization remain outstanding; subsequent signing and error-reporting work is recorded below.

**Confirmed by automated tests — 2026-09-28:** nine Swift Testing tests now exercise the app's extracted `WindowGeometry` code via `swift test` or `make test`. Coverage includes layout bounds, half/quadrant cycle order and reset, fractional sizes, display-transfer geometry, coordinate conversion, and display selection. No real windows or Accessibility permissions are needed for these tests.

Two regression tests failed against the original geometry and passed after fixes:

- AX/AppKit conversion now uses the primary display's top edge, rather than the maximum top edge across all displays. A display above the primary display previously shifted every converted window frame. Apple's [NSScreen.screens documentation](https://developer.apple.com/documentation/appkit/nsscreen/screens) identifies index zero as the primary display with origin `(0, 0)`.
- A window spanning displays now selects the display with the greatest intersection area, rather than the first intersecting display. Equal areas keep display order; zero overlap falls back to `NSScreen.main` in the controller.

These are replacement correctness fixes, not new evidence of legacy behavior. GUI shortcut/menu delivery, actual AX resize acceptance, physical multi-display operation, and failure feedback are not covered by the geometry suite. The [README automation plan](README.md#next-automation-layer) describes the remaining opt-in integration checks.

**Confirmed by runtime failure and macOS logs — 2026-09-28:** after rebuilding with `make run`, the user reported that both keyboard shortcuts and menu commands stopped moving windows. `tccd` logged `Failed to match existing code requirement` for `local.OptimalLayout` and `kTCCServiceAccessibility`, showing that the prior universal build's code hashes did not match the new native debug build. This is an invalidated Accessibility grant, not a geometry-test failure. Recovery is to quit OL, remove and re-add the current app in Accessibility settings, then reopen it without rebuilding.

**Confirmed by runtime behavior — user-reported, 2026-09-28:** resetting Accessibility access restored window control after the rebuild failure. This confirms the diagnosed permission issue and recovery procedure.

Both command entry points now share a trust check and show recovery instructions when permission is missing. The build script accepts `CODE_SIGN_IDENTITY` for certificate signing. Geometry tests do not validate TCC permission persistence; the new recovery dialog still needs runtime verification.

**Confirmed by signing inspection and runtime permission checks — 2026-09-28:** the M4 Air already has a valid `Developer ID Application: Quality Time Studio LLC (6HA2HQH2U5)` identity. Sandboxed Keychain inspection had incorrectly appeared to show no valid identities; inspection with Keychain access found the existing certificate. Its reference is now saved in git-ignored `.codesign-identity`, and the build script uses that file unless `CODE_SIGN_IDENTITY` overrides it. Unconfigured builds fail explicitly; ad-hoc signing requires an explicit `-` identity.

The user granted Accessibility once after the change to certificate signing. `make check-accessibility` then reported `Accessibility: allowed` for the native debug bundle. After quitting OL and replacing it with a certificate-signed universal release, the same check still reported `Accessibility: allowed`, with no permission reset. The binaries' code hashes differed, their designated requirements were identical, and strict signature validation passed. This directly verifies that the grant survived a changed build with the stable identity on this Mac.

The check launches the actual app through Launch Services with `--check-accessibility`, reads `AXIsProcessTrusted()`, and exits before shortcut registration or the app event loop. It does not move windows or grant permissions. The existing nine geometry tests also pass. Distribution notarization remains outside this local development setup.

**Failure reporting implemented — 2026-09-28:** focused-window and frame access now propagate Accessibility errors and validate returned CF/AX types instead of silently returning or inventing zero frames. Position and size are checked for writability before either is changed. A failed position write prevents resize; a failed size write after movement explicitly reports a partial change. Failed layout attempts retain their cycle position. Missing applications/windows/displays and single-display Switch Display attempts have explicit messages.

Global shortcuts now request exclusive Carbon registration and retain individual failures while continuing with other shortcuts. Event-handler installation and event decoding are checked. The menu-bar label changes to `OL!` when problems exist; menu details identify affected shortcuts or the last failed window command. Window failures beep without opening a dialog automatically. Successful window commands clear only the window error, preserving shortcut warnings. Registrations and the event handler are released at termination.

**Confirmed by automated tests:** the suite now has 24 passing tests: nine geometry tests and fifteen failure tests (two parameterized). Injected C API responses exercise absent/wrong-type focused windows, failed reads, malformed frames, unwritable attributes, rejected moves/resizes, partial changes, successful writes, cycle preservation, shortcut conflicts/unexpected errors, continued registration, and warning retention. These tests do not register real shortcuts or move windows. Physical shortcut conflicts and GUI warning presentation still need integration testing; applications that return success while clamping frames require future read-back verification.

**Confirmed by native runtime check — 2026-09-28:** after launching the signed universal app, a temporary second process compiled with the production `Shortcut` implementation attempted to register all five exclusive combinations. Every attempt returned `eventHotKeyExistsErr` (`-9878`), with the correct shortcut-specific message. The probe sent no keyboard events or window commands. Strict signature verification passed and `make check-accessibility` still reported allowed. This verifies actual Carbon conflict detection; GUI warning presentation and actual window-operation failure feedback remain to be exercised by a GUI harness.
