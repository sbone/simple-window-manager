import AppKit
import ApplicationServices
import Carbon.HIToolbox

private enum Layout: UInt32, CaseIterable {
    case one = 1, two, three, four

    var title: String { "Layout \(rawValue)" }
}

private final class WindowController {
    private var cycle: [Layout: Int] = [:]

    func apply(_ layout: Layout) {
        guard let window = focusedWindow(), let screen = screen(for: window) else { return }
        let frame = targetFrame(for: layout, screen: screen)
        setFrame(frame, on: window)
    }

    func switchDisplay() {
        guard let window = focusedWindow(), let current = screen(for: window) else { return }
        let screens = NSScreen.screens
        guard screens.count > 1, let index = screens.firstIndex(of: current) else { return }
        let next = screens[(index + 1) % screens.count]
        let oldFrame = appKitFrame(of: window)
        let source = current.visibleFrame
        let destination = next.visibleFrame
        let x = (oldFrame.minX - source.minX) / source.width
        let y = (oldFrame.minY - source.minY) / source.height
        let frame = CGRect(
            x: destination.minX + x * destination.width,
            y: destination.minY + y * destination.height,
            width: oldFrame.width,
            height: oldFrame.height
        )
        setFrame(frame, on: window)
    }

    private func targetFrame(for layout: Layout, screen: NSScreen) -> CGRect {
        let usable = screen.visibleFrame
        switch layout {
        case .one:
            return usable
        case .two:
            let right = cycle[.two, default: 0] % 2 == 1
            cycle[.two] = (cycle[.two, default: 0] + 1) % 2
            return CGRect(x: right ? usable.midX : usable.minX, y: usable.minY,
                          width: usable.width / 2, height: usable.height)
        case .three:
            return CGRect(x: usable.minX + usable.width / 4, y: usable.minY,
                          width: usable.width / 2, height: usable.height)
        case .four:
            let quadrant = cycle[.four, default: 0] % 4
            cycle[.four] = (quadrant + 1) % 4
            let column = quadrant == 1 || quadrant == 2 ? 1 : 0
            let row = quadrant >= 2 ? 0 : 1
            return CGRect(x: usable.minX + CGFloat(column) * usable.width / 2,
                          y: usable.minY + CGFloat(row) * usable.height / 2,
                          width: usable.width / 2, height: usable.height / 2)
        }
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
        return NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
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
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        return CGRect(x: frame.minX, y: maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement) {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? frame.maxY
        var point = CGPoint(x: frame.minX, y: maxY - frame.maxY)
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private var hotkeys: [EventHotKeyRef?] = []
    private var statusItem: NSStatusItem!

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
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        installHotkeys()
    }

    @objc private func apply(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? UInt32, let layout = Layout(rawValue: raw) else { return }
        windows.apply(layout)
    }

    @objc private func switchDisplay() { windows.switchDisplay() }

    private func installHotkeys() {
        let type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let layout = Layout(rawValue: id.id) { delegate.windows.apply(layout) }
            if id.id == 0 { delegate.windows.switchDisplay() }
            return noErr
        }, 1, [type], Unmanaged.passUnretained(self).toOpaque(), nil)

        for layout in Layout.allCases {
            var ref: EventHotKeyRef?
            var id = EventHotKeyID(signature: OSType(0x4F4C0000), id: layout.rawValue)
            RegisterEventHotKey(UInt32(18 + layout.rawValue - 1), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            hotkeys.append(ref)
        }
        var displayRef: EventHotKeyRef?
        var displayID = EventHotKeyID(signature: OSType(0x4F4C0000), id: 0)
        RegisterEventHotKey(29, UInt32(cmdKey | optionKey), displayID, GetApplicationEventTarget(), 0, &displayRef)
        hotkeys.append(displayRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
