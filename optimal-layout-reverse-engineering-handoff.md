# Optimal Layout Reverse-Engineering Handoff

## Progress Update — 2026-09-28

The local app bundle has been inspected and the initial findings are recorded in [optimal-layout-reverse-engineering.md](optimal-layout-reverse-engineering.md).

Confirmed so far:

- The legacy binary is `x86_64` only; the replacement must be universal.
- Layouts are stored as percentage rectangles in `windowPositions`.
- The app uses Accessibility APIs for window access and Carbon global hotkeys.
- The app has substantially more functionality than the intended replacement needs.

The replacement scope is now intentionally smaller: four built-in layout commands shown in the menu, global shortcuts, focused-window move/resize, next-display movement, Accessibility onboarding, and a minimal menu-bar/preferences UI. Users will not define custom window shapes or sizes, and layouts will not be assigned to specific applications. Every command applies to the currently focused eligible window. `⌘⌥2` cycles left half → right half → left half. `⌘⌥4` cycles upper-left → upper-right → lower-right → lower-left → upper-left. Each command starts its cycle at the first position on its initial press. Window browsing, grid navigation, incremental movement/resizing, tab handling, ignored-window configuration, Growl, TotalFinder, crash reporting, and update infrastructure are legacy reference behavior rather than MVP requirements.

The next investigation step is runtime verification of screen-frame semantics and Switch Display behavior, followed by a minimal vertical-slice implementation.

That implementation has now started as a dependency-free Swift package in `Package.swift` and `Sources/OptimalLayout/main.swift`. It contains the menu-bar entry point, built-in layout cycles, Carbon hotkeys, Accessibility focused-window lookup, and initial multi-display movement logic. Runtime verification remains outstanding.

## Goal

Reverse-engineer the behavior and implementation approach of the legacy macOS app **Optimal Layout 2.3.2** so we can build a clean-room replacement for **macOS 14+**, supporting both:

- Apple Silicon (`arm64`)
- Intel (`x86_64`)

The replacement should prioritize:

- very fast keyboard-driven window placement
- low overhead
- reliable global shortcuts
- four built-in window layouts
- multi-display behavior
- compatibility with modern macOS Accessibility APIs
- minimal UI and dependencies

Do **not** attempt to copy proprietary source code verbatim. The goal is to understand behavior, data structures, APIs, and implementation patterns well enough to produce a clean-room reimplementation.

---

## Known Behavior

From the existing app's Preferences window:

### Positions tab

There are custom positions bound to shortcuts such as:

- `⌘⌥1`
- `⌘⌥2`
- `⌘⌥3`
- `⌘⌥4`

There is also:

- `⌘⌥0` → **Switch Display**

Each layout row appears to support:

- Position preview
- Shortcut
- Global shortcut enabled/disabled
- Show in menu
- Possibly another visibility/menu option
- Type (`Custom Layout`, `Switch Display`)

The UI says:

> To edit a position, double-click the position you wish to change. Re-order the positions by dragging and dropping them.

Other tabs visible:

- General
- Style
- Shortcuts
- Positions
- Ignored Windows
- Updates
- About

---

## Product Hypothesis

The useful core of the app is likely small:

1. Listen for a global shortcut.
2. Determine the frontmost app.
3. Obtain the currently focused/main window through macOS Accessibility APIs.
4. Determine which display the window belongs to.
5. Calculate a target rectangle.
6. Set window position and size.
7. Optionally move the window to another display.
8. Ignore configured apps/windows.
9. Show minimal UI/overlay feedback.

Likely modern implementation:

- Swift
- AppKit
- `ApplicationServices` / `AXUIElement`
- `NSScreen`
- `NSWorkspace`
- `UserDefaults` or Codable preferences
- native global hotkey registration
- Developer ID signing + notarization
- probably distributed outside the Mac App Store

---

# Phase 1: Inspect the Installed App

Assume the app is installed at:

```bash
/Applications/Optimal Layout.app
```

If not, locate it first.

Do not modify the app.

## Basic bundle inspection

Run:

```bash
APP="/Applications/Optimal Layout.app"

find "$APP/Contents" -maxdepth 3 -type f | sort
```

Inspect the plist:

```bash
plutil -p "$APP/Contents/Info.plist"
```

Identify executable name:

```bash
defaults read "$APP/Contents/Info" CFBundleExecutable
```

Then:

```bash
BIN="$APP/Contents/MacOS/<EXECUTABLE_NAME>"

file "$BIN"
lipo -info "$BIN" 2>/dev/null || true
```

Report:

- architecture(s)
- deployment target if discoverable
- bundle identifier
- version
- copyright/vendor info
- launch agent/helper processes
- login-item behavior
- embedded frameworks
- update framework

---

# Phase 2: Inspect Linked Frameworks

Run:

```bash
otool -L "$BIN"
```

Also inspect load commands:

```bash
otool -l "$BIN"
```

Look specifically for references to:

- AppKit
- Carbon
- ApplicationServices
- Accessibility frameworks
- CoreGraphics
- Quartz
- Sparkle
- MASShortcut
- ShortcutRecorder
- Growl
- old third-party frameworks

Report which dependencies appear relevant to:

- global shortcuts
- window movement
- display handling
- preferences
- update checking

---

# Phase 3: Inspect Symbols and Objective-C Metadata

Start with:

```bash
nm -m "$BIN" | head -200
```

Then search for likely symbols:

```bash
nm -m "$BIN" | grep -Ei 'window|screen|display|layout|shortcut|hotkey|position|access|AX|ignore|menu|move|resize'
```

Run:

```bash
strings "$BIN" > /tmp/optimal-layout-strings.txt
```

Search:

```bash
grep -Ei \
'window|screen|display|layout|shortcut|hotkey|position|ignored|AXUI|accessibility|menu|resize|move|Sparkle|defaults|preferences' \
/tmp/optimal-layout-strings.txt
```

If Objective-C metadata is present, inspect class and selector names.

If available, try `class-dump`:

```bash
class-dump "$BIN" > /tmp/optimal-layout-classes.txt
```

If `class-dump` fails due to binary age/format, note that and continue.

Look for classes that appear related to:

- layout definitions
- screen/display abstraction
- shortcut registration
- window manipulation
- preferences
- ignored-window rules
- overlay/HUD drawing

Do not spend excessive time reconstructing unrelated UI classes.

---

# Phase 4: Inspect Resources

Search for:

- `.nib`
- `.xib`
- `.storyboard`
- `.plist`
- `.strings`
- images
- bundled defaults
- templates
- JSON/XML preference schemas

Commands:

```bash
find "$APP/Contents/Resources" -type f | sort
```

If compiled nibs exist, inspect their metadata where feasible.

Search all textual resources:

```bash
grep -RniE \
'layout|position|shortcut|ignored|window|screen|display|menu|global' \
"$APP/Contents/Resources" 2>/dev/null
```

Report any useful preference labels or hidden features.

---

# Phase 5: Find Preference Storage

Determine the bundle identifier:

```bash
defaults read "$APP/Contents/Info" CFBundleIdentifier
```

Then inspect app preferences:

```bash
defaults read <BUNDLE_ID>
```

Also check:

```bash
ls -la ~/Library/Preferences | grep -i optimal
```

Search for related files:

```bash
find ~/Library \
  \( -iname '*optimal*layout*' -o -iname '*optimallayout*' \) \
  2>/dev/null
```

Important: do not delete or mutate user settings.

Document:

- preference keys
- how layouts are serialized
- shortcut representation
- ignored-window rules
- ordering
- menu visibility flags
- style settings
- display handling preferences

If layout data is opaque/binary, identify format if possible.

---

# Phase 6: Accessibility / Window-Control Investigation

Determine whether the app appears to use:

- `AXUIElement`
- `AXUIElementCopyAttributeValue`
- `AXUIElementSetAttributeValue`
- `kAXFocusedWindowAttribute`
- `kAXMainWindowAttribute`
- `kAXPositionAttribute`
- `kAXSizeAttribute`
- `AXIsProcessTrusted`
- CoreGraphics window APIs
- private APIs

Search symbols and strings for:

```text
AXUIElement
AXIsProcessTrusted
kAXFocusedWindowAttribute
kAXMainWindowAttribute
kAXPositionAttribute
kAXSizeAttribute
```

If exact symbol names are absent, inspect disassembly around calls into:

- ApplicationServices
- HIServices
- CoreGraphics

The key question is:

> Is Optimal Layout using public Accessibility APIs to move/resize windows, or something older/private?

Report evidence, not guesses.

---

# Phase 7: Global Shortcut Implementation

Determine how global shortcuts are registered.

Potential possibilities:

- Carbon `RegisterEventHotKey`
- MASShortcut
- ShortcutRecorder
- event tap
- `NSEvent` global monitor
- custom helper

Search for:

```text
RegisterEventHotKey
EventHotKey
CGEventTap
NSEvent
MASShortcut
ShortcutRecorder
```

Report:

- mechanism
- whether shortcuts are system-global
- how key combinations are stored
- whether conflicts appear to be detected

---

# Phase 8: Multi-Display Behavior

Investigate specifically how **Switch Display** likely works.

Look for APIs or strings involving:

- `NSScreen`
- `CGGetActiveDisplayList`
- display IDs
- visible frame
- screen frame
- menu bar / Dock insets

We need to determine whether switching displays:

1. preserves absolute pixel size
2. preserves relative size
3. preserves relative x/y position
4. moves to equivalent quadrant
5. centers the window
6. cycles through displays

If static analysis is insufficient, create a runtime test plan rather than guessing.

---

# Phase 9: Runtime Behavior Tests

After static inspection, run the app and document observable behavior.

Do **not** alter persistent preferences unless necessary.

Test with a normal resizable app window.

For each layout shortcut:

- current window frame before
- target screen
- resulting frame after
- whether animation occurs
- whether menu bar/Dock are avoided
- whether repeated presses change anything
- behavior near screen edges
- behavior on a second display

Use a small helper script if useful to log frontmost window geometry before/after.

Also test:

- Finder
- Safari
- Terminal
- System Settings
- a non-resizable dialog
- floating utility/palette window if available

Record failures and special cases.

---

# Phase 10: Position Editor Investigation

The highest-value UI to inspect is the editor opened by double-clicking a Position row.

Document:

- how positions are defined
- whether they use:
  - percentages
  - pixels
  - grid cells
  - drag-to-draw rectangles
- whether multiple monitors are previewed
- whether layouts are display-relative
- whether margins/gaps exist
- whether aspect ratio is preserved
- whether minimum window sizes are respected

If possible, change one test layout temporarily, observe preference-file changes, then restore it.

This can reveal the exact serialized representation.

---

# Phase 11: Ignored Windows

Inspect the **Ignored Windows** tab.

Determine whether ignore rules match by:

- application bundle ID
- process name
- window title
- window role/subrole
- window class
- regex/string match

This matters for a clean replacement.

---

# Phase 12: Produce a Findings Report

Create:

```text
optimal-layout-reverse-engineering.md
```

Use this structure:

```markdown
# Optimal Layout 2.3.2 Reverse Engineering

## Executive Summary

## Binary / Architecture

## Frameworks and Dependencies

## Global Shortcut Implementation

## Window Manipulation Implementation

## Position / Layout Data Model

## Multi-Display Behavior

## Ignored Window Behavior

## Preference Storage

## UI / Overlay Behavior

## Legacy / Obsolete APIs

## Behavior That Can Be Reimplemented with Public APIs

## Behavior That Requires Runtime Verification

## Risks / Unknowns

## Proposed Modern Architecture

## Suggested MVP
```

---

# Proposed Modern Replacement Architecture

Unless reverse-engineering shows a compelling reason otherwise, evaluate this baseline:

## App

- Swift
- AppKit-first
- SwiftUI only where it simplifies Preferences
- macOS 14 minimum

## Window control

- `AXUIElement`
- frontmost application from `NSWorkspace`
- focused window via Accessibility
- set `kAXPositionAttribute`
- set `kAXSizeAttribute`

## Display handling

- `NSScreen`
- define four built-in layouts against `visibleFrame`

Example model:

```swift
enum BuiltInLayout {
    case first
    case second
    case third
    case fourth
}

struct WindowLayout {
    var name: String
    var frame: CGRect
}
```

The four frames are product-defined constants. They are not user-editable and are not assigned to particular applications.

## Special actions

Represent actions separately:

```swift
enum WindowAction: Codable {
    case layout(WindowLayout)
    case switchDisplay
}
```

## Preferences

Prefer:

- UserDefaults for shortcut settings and basic preferences
- no database

## Distribution

Likely:

- Developer ID signed
- notarized
- direct download
- optional Sparkle updates

Evaluate sandbox implications before deciding on Mac App Store distribution.

---

# MVP Definition

The first replacement version should probably support only:

1. Launch at login
2. Accessibility permission onboarding
3. Global shortcuts
4. Four built-in screen-relative layouts
5. Move/resize focused window
6. Switch focused window to next display
7. Simple menu-bar and Preferences UI
8. Universal binary
9. macOS 14+

Avoid adding:

- full tiling
- automatic window management
- elaborate snapping
- mouse gestures
- scripting
- workspace profiles
- cloud sync
- telemetry

unless reverse-engineering reveals that an existing behavior is genuinely important.

---

# Questions to Answer During Reverse Engineering

Prioritize these:

1. How exactly are layouts represented internally?
2. Are positions pixel-based or proportional?
3. Does the app use `visibleFrame` or full screen bounds?
4. How does Switch Display calculate destination geometry?
5. Does repeated activation cycle layouts or states?
6. What global hotkey API is used?
7. How are ignored windows identified?
8. Does the app animate window movement?
9. Is there an overlay/HUD?
10. Does it use private APIs?
11. Are there any behaviors modern macOS APIs cannot reproduce?
12. Are there any important defaults or edge-case rules worth preserving?

---

# Working Style

Prefer empirical evidence over assumptions.

For every conclusion, label it as one of:

- **Confirmed by binary/static inspection**
- **Confirmed by runtime behavior**
- **Likely**
- **Unknown**

Do not over-invest in perfect decompilation.

The primary goal is to derive a clean, modern behavioral specification and implementation plan for a replacement app.
