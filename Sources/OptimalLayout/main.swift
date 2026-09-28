import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
private final class WindowController {
    private var geometry = WindowGeometry()

    func apply(_ layout: Layout) {
        guard let window = focusedWindow(), let screen = screen(for: window) else { return }
        let frame = geometry.targetFrame(for: layout, usable: screen.visibleFrame)
        setFrame(frame, on: window)
    }

    func switchDisplay() {
        guard let window = focusedWindow(), let current = screen(for: window) else { return }
        let screens = NSScreen.screens
        guard screens.count > 1, let index = screens.firstIndex(of: current) else { return }
        let next = screens[(index + 1) % screens.count]
        let oldFrame = appKitFrame(of: window)
        let frame = WindowGeometry.movedFrame(oldFrame, from: current.visibleFrame, to: next.visibleFrame)
        setFrame(frame, on: window)
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        return (value as! AXUIElement)
    }

    private func screen(for window: AXUIElement) -> NSScreen? {
        let frame = appKitFrame(of: window)
        let screens = NSScreen.screens
        guard let index = WindowGeometry.screenIndex(for: frame, screens: screens.map(\.frame)) else { return NSScreen.main }
        return screens[index]
    }

    private func accessibilityFrame(of window: AXUIElement) -> CGRect {
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        if let position { AXValueGetValue(position as! AXValue, .cgPoint, &point) }
        if let size { AXValueGetValue(size as! AXValue, .cgSize, &dimensions) }
        return CGRect(origin: point, size: dimensions)
    }

    private func appKitFrame(of window: AXUIElement) -> CGRect {
        let frame = accessibilityFrame(of: window)
        return WindowGeometry.flippedFrame(frame, screens: NSScreen.screens.map(\.frame))
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement) {
        var point = WindowGeometry.flippedFrame(frame, screens: NSScreen.screens.map(\.frame)).origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private var hotkeys: [EventHotKeyRef?] = []
    private var statusItem: NSStatusItem!
    private var showingPermissionAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "OL"
        let menu = NSMenu()
        for layout in Layout.allCases {
            let item = menu.addItem(withTitle: layout.title, action: #selector(apply(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
        }
        menu.addItem(.separator())
        let switchItem = menu.addItem(withTitle: "Switch Display", action: #selector(switchDisplay), keyEquivalent: "")
        switchItem.target = self
        menu.addItem(.separator())
        let accessibilityItem = menu.addItem(withTitle: "Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        installHotkeys()
        requestAccessibility()
    }

    @objc private func requestAccessibility() {
        // The SDK imports the equivalent C constant as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func apply(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? UInt32 else { return }
        performAction(raw)
    }

    @objc private func switchDisplay() { performAction(0) }

    private func performAction(_ id: UInt32) {
        guard AXIsProcessTrusted() else {
            guard !showingPermissionAlert else { return }
            showingPermissionAlert = true
            defer { showingPermissionAlert = false }
            let alert = NSAlert()
            alert.messageText = "Accessibility permission is needed"
            alert.informativeText = "Allow Optimal Layout in System Settings → Privacy & Security → Accessibility. If it is already enabled, quit Optimal Layout, remove its entry, add this copy of the app again, and reopen it."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
            return
        }
        if let layout = Layout(rawValue: id) { windows.apply(layout) }
        if id == 0 { windows.switchDisplay() }
    }

    private func installHotkeys() {
        let type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Application event-target callbacks run on the main event loop.
            MainActor.assumeIsolated { delegate.performAction(id.id) }
            return noErr
        }, 1, [type], Unmanaged.passUnretained(self).toOpaque(), nil)

        for layout in Layout.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4F4C0000), id: layout.rawValue)
            RegisterEventHotKey(UInt32(18 + layout.rawValue - 1), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            hotkeys.append(ref)
        }
        var displayRef: EventHotKeyRef?
        let displayID = EventHotKeyID(signature: OSType(0x4F4C0000), id: 0)
        RegisterEventHotKey(29, UInt32(cmdKey | optionKey), displayID, GetApplicationEventTarget(), 0, &displayRef)
        hotkeys.append(displayRef)
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
