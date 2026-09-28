import AppKit
import ApplicationServices

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// Only inspect OL's process. Keep AX objects on the worker that creates them;
// blocking AX calls must not prevent our test window from serving OL's AX requests.
enum UI {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    static func text(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
            .compactMap { value(element, $0) as? String }.joined(separator: " ")
    }

    static func find(_ roots: [AXUIElement], depth: Int = 0, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth < 8 else { return nil }
        for element in roots {
            if matching(element) { return element }
            if let found = find(children(element), depth: depth + 1, matching: matching) { return found }
        }
        return nil
    }

    static func statusItem(_ app: AXUIElement) -> AXUIElement? {
        guard let bar = value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        return children(bar as! AXUIElement).first
    }

    static func press(_ element: AXUIElement) throws {
        AXUIElementSetMessagingTimeout(element, 1)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        // Menu tracking / modal alerts can outlive the AX request. The caller
        // still verifies the resulting menu, alert, or frame with a deadline.
        guard result == .success || result == .cannotComplete else { throw SmokeFailure("AXPress failed: \(result.rawValue)") }
    }

    @concurrent
    static func status(pid: pid_t) async -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let item = statusItem(app) else { return nil }
        return text(item)
    }

    @concurrent
    static func menu(pid: pid_t, title: String) async throws {
        let app = AXUIElementCreateApplication(pid)
        guard let item = statusItem(app) else { throw SmokeFailure("OL's status item is missing from Accessibility") }
        try press(item)
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        repeat {
            if let command = find([item, app], matching: {
                value($0, kAXRoleAttribute) as? String == kAXMenuItemRole && value($0, kAXTitleAttribute) as? String == title
            }) {
                let ownsFocus = await MainActor.run {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
                }
                guard ownsFocus else { throw SmokeFailure("Test window lost focus; refusing to invoke \(title)") }
                try press(command)
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw SmokeFailure("Menu item not found: \(title)")
    }

    @concurrent
    static func alertContains(pid: pid_t, text expected: String) async -> Bool {
        let app = AXUIElementCreateApplication(pid)
        return find(children(app, kAXWindowsAttribute), matching: { text($0).contains(expected) }) != nil
    }

    @concurrent
    static func dismissAlert(pid: pid_t) async throws {
        let app = AXUIElementCreateApplication(pid)
        guard let button = find(children(app, kAXWindowsAttribute), matching: {
            value($0, kAXRoleAttribute) as? String == kAXButtonRole && value($0, kAXTitleAttribute) as? String == "OK"
        }) else { throw SmokeFailure("Could not find the problem dialog's OK button") }
        try press(button)
    }

    @concurrent
    static func sizeIsSettable(pid: pid_t) async -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = value(app, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var result: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window as! AXUIElement, kAXSizeAttribute as CFString, &result) == .success else { return nil }
        return result.boolValue
    }

    @concurrent
    static func snapshot(pid: pid_t) async -> String {
        let app = AXUIElementCreateApplication(pid)
        var lines: [String] = []
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 7, lines.count < 100 else { return }
            lines.append(String(repeating: "  ", count: depth) + "\(value(element, kAXRoleAttribute) as? String ?? "?"): \(text(element))")
            for child in children(element) { visit(child, depth: depth + 1) }
        }
        for attribute in [kAXExtrasMenuBarAttribute, kAXMenuBarAttribute] {
            if let bar = value(app, attribute), CFGetTypeID(bar) == AXUIElementGetTypeID() { visit(bar as! AXUIElement, depth: 0) }
        }
        for window in children(app, kAXWindowsAttribute) { visit(window, depth: 0) }
        return lines.joined(separator: "\n")
    }
}
