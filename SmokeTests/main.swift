import AppKit
import ApplicationServices
import Carbon.HIToolbox

func report(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

@MainActor
final class SmokeRunner: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var ol: NSRunningApplication?
    private var reservedHotkey: EventHotKeyRef?
    private var cancelled = false
    private var cleaningUp = false
    private var restoringLoginItem = false
    private var passed = 0
    private var skipped = 0
    private var appURL: URL!
    private var screen: NSScreen!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI lifecycle entry point: the task owns this run and handles all errors.
        Task { await run() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if cleaningUp { return .terminateNow }
        cancelled = true
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { cancelled = true; return false }
    @objc private func stop() { cancelled = true }

    private func run() async {
        guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--login-item") else {
            finish("FAIL: expected the OL app path and optional --login-item", code: 1); return
        }
        appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            report("BLOCKED: Enable OL Smoke Test in System Settings → Privacy & Security → Accessibility, then rerun make smoke-test.")
            report("Helper: \(Bundle.main.bundleURL.path)")
            finish("RESULT BLOCKED", code: 2)
            return
        }
        guard let primary = NSScreen.screens.first else { finish("FAIL: no displays", code: 1); return }
        screen = primary
        report("Testing on \(NSScreen.screens.count) display(s); frame tolerance: 2 points; timeout: 4 seconds.")
        makeWindow()
        var failure: Error?
        do {
            try await placements(usingMenu: false)
            try await placements(usingMenu: true)
            try await windowWarning()
            try await shortcutWarning()
            try await displayTransfers()
            if CommandLine.arguments.contains("--login-item") { try await loginItem() }
        } catch {
            failure = error
            report("FAIL: \(error)")
            if let ol { report("OL Accessibility snapshot:\n" + (await UI.snapshot(pid: ol.processIdentifier))) }
        }
        cleaningUp = true
        if let reservedHotkey { UnregisterEventHotKey(reservedHotkey); self.reservedHotkey = nil }
        window.close()
        do { try await stopOL() } catch { failure = failure ?? error; report("FAIL cleanup: \(error)") }
        report("Summary: \(passed) passed, \(skipped) skipped\(failure == nil ? "" : ", run stopped on failure")")
        finish(failure == nil ? "RESULT PASS" : "RESULT FAIL", code: failure == nil ? 0 : 1)
    }

    private func finish(_ message: String, code: Int32) { report(message); exit(code) }

    private func loginItem() async throws {
        try await restartOL()
        try await focus()
        let original = try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login", inspectOnly: true)
        guard original == "" || original == "✓" else { throw SmokeFailure("Launch at Login needs approval; resolve it in System Settings before testing") }
        var failure: Error?
        do {
            try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login")
            try await restartOL()
            try await focus()
            let changed = try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login", inspectOnly: true)
            guard changed == (original.isEmpty ? "✓" : "") else { throw SmokeFailure("Launch at Login did not persist its changed state after restart: \(changed)") }
            passed += 1
            report("PASS Launch at Login toggles and persists after app restart")
        } catch { failure = error }
        // Restore the user's original registration even if the assertion failed.
        restoringLoginItem = true
        defer { restoringLoginItem = false }
        try await focus()
        let current = try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login", inspectOnly: true)
        if current != original { try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login") }
        try await restartOL()
        try await focus()
        let restored = try await UI.menu(pid: ol!.processIdentifier, title: "Launch at Login", inspectOnly: true)
        guard restored == original else { throw SmokeFailure("Could not restore Launch at Login; check OL's menu") }
        if let failure { throw failure }
        if cancelled { throw SmokeFailure("Cancelled by user") }
        passed += 1
        report("PASS Launch at Login restored and persisted after app restart")
    }

    private func makeWindow() {
        window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 420, height: 280),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "OL Smoke Test — disposable test window"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = CGSize(width: 100, height: 100)
        let text = NSTextField(wrappingLabelWithString: "Automated window-placement checks are running.\nPlease leave the keyboard and mouse idle.")
        text.frame = CGRect(x: 20, y: 110, width: 360, height: 90)
        text.autoresizingMask = [.width, .minYMargin]
        window.contentView?.addSubview(text)
        let button = NSButton(title: "Stop Test", target: self, action: #selector(stop))
        button.frame = CGRect(x: 20, y: 40, width: 120, height: 32)
        window.contentView?.addSubview(button)
    }

    private func wait(_ description: String, checkCancellation: Bool = true, until condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        repeat {
            if checkCancellation && cancelled && !restoringLoginItem { throw SmokeFailure("Cancelled by user") }
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw SmokeFailure("Timed out: \(description)")
    }

    private func stopOL() async throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.stevenbone.optimallayout")
            .filter { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL }
        for app in apps { app.terminate() }
        try await wait("OL to quit", checkCancellation: false) { apps.allSatisfy(\.isTerminated) }
        ol = nil
    }

    private func restartOL() async throws {
        try await stopOL()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["-SUEnableAutomaticChecks", "NO"]
        ol = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await wait("OL menu-bar item") { await UI.status(pid: self.ol!.processIdentifier) != nil }
    }

    private func focus() async throws {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try await wait("test window to take focus") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier && self.window.isKeyWindow
        }
    }

    private func seed() async throws {
        let usable = screen.visibleFrame
        window.setFrame(CGRect(x: usable.minX + 73, y: usable.minY + 61, width: usable.width * 0.37, height: usable.height * 0.43), display: true)
        try await focus()
    }

    private func key(_ code: Int) throws {
        guard !cancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            throw SmokeFailure("Test window lost focus; refusing to send a shortcut")
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: false) else {
            throw SmokeFailure("Could not create keyboard events")
        }
        down.flags = [.maskCommand, .maskAlternate]
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func expectFrame(_ expected: CGRect, named name: String) async throws {
        var stableSamples = 0
        do {
            try await wait(name) {
                let actual = self.window.frame
                let close = zip([actual.minX, actual.minY, actual.width, actual.height],
                                [expected.minX, expected.minY, expected.width, expected.height]).allSatisfy { abs($0 - $1) <= 2 }
                stableSamples = close ? stableSamples + 1 : 0
                return stableSamples >= 3
            }
        } catch {
            throw SmokeFailure("\(name): expected \(expected), actual \(window.frame); \(error)")
        }
        passed += 1
        report("PASS \(name): \(window.frame)")
    }

    private func placements(usingMenu: Bool) async throws {
        try await restartOL()
        let usable = screen.visibleFrame
        // These expected rectangles come from the product spec, not production geometry code.
        let cases: [(Int, Int, [CGFloat])] = [
            (1, kVK_ANSI_1, [0, 0, 1, 1]), (3, kVK_ANSI_3, [0.25, 0, 0.5, 1]),
            (2, kVK_ANSI_2, [0, 0, 0.5, 1]), (2, kVK_ANSI_2, [0.5, 0, 0.5, 1]), (2, kVK_ANSI_2, [0, 0, 0.5, 1]),
            (4, kVK_ANSI_4, [0, 0.5, 0.5, 0.5]), (4, kVK_ANSI_4, [0.5, 0.5, 0.5, 0.5]),
            (4, kVK_ANSI_4, [0.5, 0, 0.5, 0.5]), (4, kVK_ANSI_4, [0, 0, 0.5, 0.5]), (4, kVK_ANSI_4, [0, 0.5, 0.5, 0.5])
        ]
        let titles = [1: "Fill Screen", 2: "Cycle Left / Right Half", 3: "Center Half Width", 4: "Cycle Corners"]
        for (index, test) in cases.enumerated() {
            try await seed()
            if usingMenu { try await UI.menu(pid: ol!.processIdentifier, title: titles[test.0]!) }
            else { try key(test.1) }
            let f = test.2
            let expected = CGRect(x: usable.minX + usable.width * f[0], y: usable.minY + usable.height * f[1],
                                  width: usable.width * f[2], height: usable.height * f[3])
            try await expectFrame(expected, named: "\(usingMenu ? "Menu" : "Shortcut") Layout \(test.0), step \(index + 1)")
        }
    }

    private func expectStatus(warning: Bool) async throws {
        try await wait(warning ? "warning icon" : "warning to clear") {
            guard let text = await UI.status(pid: self.ol!.processIdentifier) else { return false }
            return text.contains("Optimal Layout needs attention") == warning
        }
    }

    private func showWarning(menuTitle: String, containing message: String) async throws {
        try await UI.menu(pid: ol!.processIdentifier, title: menuTitle)
        try await wait("problem dialog containing '\(message)'") { await UI.alertContains(pid: self.ol!.processIdentifier, text: message) }
        try await UI.dismissAlert(pid: ol!.processIdentifier)
        try await wait("problem dialog to close") { !(await UI.alertContains(pid: self.ol!.processIdentifier, text: message)) }
    }

    private func windowWarning() async throws {
        try await restartOL()
        try await seed()
        window.styleMask.remove(.resizable)
        defer { window.styleMask.insert(.resizable) }
        guard await UI.sizeIsSettable(pid: ProcessInfo.processInfo.processIdentifier) == false else {
            throw SmokeFailure("Non-resizable test window still advertises a writable AX size")
        }
        let before = window.frame
        try key(kVK_ANSI_2)
        try await expectStatus(warning: true)
        try await expectFrame(before, named: "Rejected resize leaves test window unchanged")
        try await showWarning(menuTitle: "Window Command Failed…", containing: "does not allow changes to its size")
        passed += 1
        report("PASS window-failure warning and dialog")
        window.styleMask.insert(.resizable)
        try await seed()
        try key(kVK_ANSI_2)
        let usable = screen.visibleFrame
        try await expectFrame(CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height), named: "Retry stays on first half")
        try await expectStatus(warning: false)
        passed += 1
        report("PASS successful command clears window warning")
    }

    private func shortcutWarning() async throws {
        try await stopOL()
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | optionKey),
                                         EventHotKeyID(signature: 0x534D4F4B, id: 2), GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reservedHotkey)
        guard result == noErr else { throw SmokeFailure("Could not reserve conflict-test shortcut: \(result)") }
        try await restartOL()
        try await expectStatus(warning: true)
        try await seed()
        try await showWarning(menuTitle: "Shortcut Problems…", containing: "⌘⌥2 (Cycle Left / Right Half) is already registered")
        try await seed()
        try key(kVK_ANSI_1)
        try await expectFrame(screen.visibleFrame, named: "Other shortcut works during conflict")
        try await expectStatus(warning: true)
        try await seed()
        try await UI.menu(pid: ol!.processIdentifier, title: "Cycle Left / Right Half")
        let usable = screen.visibleFrame
        try await expectFrame(CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height), named: "Conflicting shortcut's menu command still works")
        try await expectStatus(warning: true)
        passed += 1
        report("PASS shortcut warning survives successful window commands")
        if let reservedHotkey { UnregisterEventHotKey(reservedHotkey); self.reservedHotkey = nil }
        try await restartOL()
        try await expectStatus(warning: false)
    }

    private func displayTransfers() async throws {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            skipped += 1
            report("SKIP multi-display placement: only one display is connected")
            return
        }
        let width = min(400, screens.map { $0.visibleFrame.width / 4 }.min()!)
        let height = min(250, screens.map { $0.visibleFrame.height / 4 }.min()!)
        let first = screens[0].visibleFrame
        window.setFrame(CGRect(x: first.minX + first.width * 0.2, y: first.minY + first.height * 0.2, width: width, height: height), display: true)
        for index in 1...screens.count {
            try await focus()
            if index.isMultiple(of: 2) { try await UI.menu(pid: ol!.processIdentifier, title: "Move to Next Display") }
            else { try key(kVK_ANSI_0) }
            let destination = screens[index % screens.count].visibleFrame
            try await expectFrame(CGRect(x: destination.minX + destination.width * 0.2, y: destination.minY + destination.height * 0.2,
                                         width: width, height: height), named: "Switch Display to index \(index % screens.count)")
        }
    }
}

let app = NSApplication.shared
let runner = SmokeRunner()
app.delegate = runner
app.run()
