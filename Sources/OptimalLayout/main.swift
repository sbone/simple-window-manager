import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement
import Sparkle
import SwiftUI

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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let windows = WindowController()
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var statusItem: NSStatusItem!
    private var showingPermissionAlert = false
    private var settingsWindow: NSWindow?
    private lazy var settings = SettingsModel(updaterController: updaterController)
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private let problemItem = NSMenuItem(title: "Show Problems…", action: #selector(showProblems), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let loginSettingsItem = NSMenuItem(title: "Approve Launch at Login…", action: #selector(openLoginSettings), keyEquivalent: "")
    private let automaticUpdatesItem = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        problemItem.target = self
        problemItem.isHidden = true
        menu.addItem(problemItem)
        for layout in Layout.allCases {
            let item = menu.addItem(withTitle: layout.title, action: #selector(apply(_:)), keyEquivalent: String(layout.rawValue))
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            item.representedObject = layout.rawValue
        }
        menu.addItem(.separator())
        let switchItem = menu.addItem(withTitle: "Move to Next Display", action: #selector(switchDisplay), keyEquivalent: "0")
        switchItem.keyEquivalentModifierMask = [.command, .option]
        switchItem.target = self
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        let accessibilityItem = menu.addItem(withTitle: "Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        loginItem.target = self
        loginSettingsItem.target = self
        menu.addItem(loginItem)
        menu.addItem(loginSettingsItem)
        updateLoginItem()
        menu.addItem(.separator())
        let updatesItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = updaterController
        automaticUpdatesItem.target = self
        menu.addItem(automaticUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Optimal Layout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        let appMenu = NSMenu(title: "Optimal Layout")
        let settingsCommand = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsCommand.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Optimal Layout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
        installHotkeys()
        requestAccessibility()
    }

    func menuWillOpen(_ menu: NSMenu) {
        settings.refresh()
        updateLoginItem()
        automaticUpdatesItem.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
    }

    @objc private func toggleAutomaticUpdates() {
        settings.refresh()
        settings.automaticallyChecksForUpdates.toggle()
    }

    private func updateLoginItem() {
        let status = SMAppService.mainApp.status
        loginItem.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        loginSettingsItem.isHidden = status != .requiresApproval
    }

    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    @objc private func toggleLaunchAtLogin() {
        settings.refresh()
        settings.launchAtLogin.toggle()
        updateLoginItem()
        if settings.loginError != nil { showSettings() }
        else if settings.loginStatus == .requiresApproval { openLoginSettings() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        settings.refresh()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        settings.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Optimal Layout Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
            window.center()
            window.setFrameAutosaveName("Settings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func requestAccessibility() {
        // The SDK imports the equivalent C constant as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func openAccessibilitySettings() { settings.openAccessibilitySettings() }

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
            settings.problems.windowFailure = nil
        } catch {
            settings.problems.windowFailure = error.localizedDescription
            NSLog("Window command %u failed: %@", id, String(describing: error))
            NSSound.beep()
        }
        updateProblems()
    }

    private func updateProblems() {
        let messages = settings.problems.messages
        let label = messages.isEmpty ? "Optimal Layout" : "Optimal Layout needs attention"
        let symbol = messages.isEmpty ? "rectangle.split.2x2" : "exclamationmark.triangle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel(label)
        statusItem.button?.toolTip = messages.isEmpty ? "Optimal Layout" : messages.joined(separator: "\n\n")
        problemItem.isHidden = messages.isEmpty
        problemItem.title = settings.problems.windowFailure == nil ? "Shortcut Problems…" : "Window Command Failed…"
    }

    @objc private func showProblems() {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = "Optimal Layout needs attention"
        alert.informativeText = settings.problems.messages.joined(separator: "\n\n")
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
            settings.problems.shortcutFailures = ["Global shortcuts could not start (macOS error \(handlerResult)). Restart OL. Menu commands are still available."]
            updateProblems()
            return
        }
        let registration = Shortcut.registerAll()
        hotkeys = registration.references
        settings.problems.shortcutFailures = registration.failures
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
