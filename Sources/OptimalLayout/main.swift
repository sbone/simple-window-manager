import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
private final class WindowController {
    private var geometry = WindowGeometry()
    private let access = WindowAccess()

    func apply(_ layout: Layout) throws {
        let window = try access.focusedWindow(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let frame = try appKitFrame(of: window)
        let screen = try screen(for: frame)
        try geometry.apply(layout, usable: screen.visibleFrame) { target in
            try access.setFrame(WindowGeometry.flippedFrame(target, screens: NSScreen.screens.map(\.frame)), on: window)
        }
    }

    func switchDisplay() throws {
        let window = try access.focusedWindow(processIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let oldFrame = try appKitFrame(of: window)
        let current = try screen(for: oldFrame)
        let screens = NSScreen.screens
        guard screens.count > 1 else { throw WindowFailure.onlyOneDisplay }
        guard let index = screens.firstIndex(of: current) else { throw WindowFailure.noDisplay }
        let next = screens[(index + 1) % screens.count]
        let target = WindowGeometry.movedFrame(oldFrame, from: current.visibleFrame, to: next.visibleFrame)
        try access.setFrame(WindowGeometry.flippedFrame(target, screens: screens.map(\.frame)), on: window)
    }

    private func screen(for frame: CGRect) throws -> NSScreen {
        let screens = NSScreen.screens
        if let index = WindowGeometry.screenIndex(for: frame, screens: screens.map(\.frame)) { return screens[index] }
        guard let screen = NSScreen.main else { throw WindowFailure.noDisplay }
        return screen
    }

    private func appKitFrame(of window: AXUIElement) throws -> CGRect {
        WindowGeometry.flippedFrame(try access.frame(of: window), screens: NSScreen.screens.map(\.frame))
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem!
    private var showingPermissionAlert = false
    private var problems = AppProblems()
    private let problemItem = NSMenuItem(title: "Show Problems…", action: #selector(showProblems), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "OL"
        let menu = NSMenu()
        problemItem.target = self
        problemItem.isHidden = true
        menu.addItem(problemItem)
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
        do {
            if let layout = Layout(rawValue: id) { try windows.apply(layout) }
            if id == 0 { try windows.switchDisplay() }
            problems.windowFailure = nil
        } catch {
            problems.windowFailure = error.localizedDescription
            NSLog("Window command %u failed: %@", id, String(describing: error))
            NSSound.beep()
        }
        updateProblems()
    }

    private func updateProblems() {
        let messages = problems.messages
        statusItem.button?.title = messages.isEmpty ? "OL" : "OL!"
        statusItem.button?.toolTip = messages.isEmpty ? "Optimal Layout" : messages.joined(separator: "\n\n")
        problemItem.isHidden = messages.isEmpty
        problemItem.title = problems.windowFailure == nil ? "Shortcut Problems…" : "Window Command Failed…"
    }

    @objc private func showProblems() {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = "Optimal Layout needs attention"
        alert.informativeText = problems.messages.joined(separator: "\n\n")
        NSApp.activate()
        alert.runModal()
        previousApp?.activate(options: [])
    }

    private func installHotkeys() {
        let type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == Shortcut.signature else { return OSStatus(eventNotHandledErr) }
            // Application event-target callbacks run on the main event loop.
            MainActor.assumeIsolated { delegate.performAction(id.id) }
            return noErr
        }, 1, [type], Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerResult == noErr else {
            problems.shortcutFailures = ["Global shortcuts could not start (macOS error \(handlerResult)). Restart OL. Menu commands are still available."]
            updateProblems()
            return
        }
        let registration = Shortcut.registerAll()
        hotkeys = registration.references
        problems.shortcutFailures = registration.failures
        for failure in registration.failures { NSLog("Shortcut registration failed: %@", failure) }
        updateProblems()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--check-accessibility") {
    let trusted = AXIsProcessTrusted()
    print(trusted ? "Accessibility: allowed" : "Accessibility: denied")
    exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
}
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
