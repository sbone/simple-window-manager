import ApplicationServices
import Foundation

enum WindowFailure: Error, LocalizedError, Equatable {
    case noApplication, noWindow, noDisplay, onlyOneDisplay
    case invalidValue(String)
    case notSettable(String)
    case accessibility(String, Int32)
    case partialResize(Int32)

    var errorDescription: String? {
        switch self {
        case .noApplication: "No active application. Focus a resizable window and try again."
        case .noWindow: "No focused window. Focus a resizable window and try again."
        case .noDisplay: "No usable display was found. Reconnect the display and try again."
        case .onlyOneDisplay: "Switch Display needs at least two connected displays."
        case .invalidValue(let attribute): "The app returned an invalid window \(attribute). Try a different window."
        case .notSettable(let attribute): "This window does not allow changes to its \(attribute). Try a normal resizable window."
        case .partialResize: "The window moved, but the app rejected resizing it. Try a different resizable window."
        case .accessibility(let operation, let code):
            switch AXError(rawValue: code) {
            case .apiDisabled: "Accessibility access is unavailable. Open Accessibility Settings from the OL menu."
            case .cannotComplete: "\(operation) failed because the app did not respond. Try again when the app is ready."
            case .invalidUIElement: "The window is no longer available. Focus a window and try again."
            case .attributeUnsupported, .notImplemented: "\(operation) is not supported by this app or window. Try a different window."
            default: "\(operation) failed. Try a different window."
            }
        }
    }
}

// Keep the C API boundary injectable so failures can be tested without controlling real windows.
@MainActor
struct WindowAccess {
    var copyAttribute: (AXUIElement, CFString, UnsafeMutablePointer<CFTypeRef?>) -> AXError = AXUIElementCopyAttributeValue
    var isSettable: (AXUIElement, CFString, UnsafeMutablePointer<DarwinBoolean>) -> AXError = AXUIElementIsAttributeSettable
    var setAttribute: (AXUIElement, CFString, CFTypeRef) -> AXError = AXUIElementSetAttributeValue

    func focusedWindow(processIdentifier: pid_t?) throws -> AXUIElement {
        guard let processIdentifier else { throw WindowFailure.noApplication }
        let app = AXUIElementCreateApplication(processIdentifier)
        let value = try read(kAXFocusedWindowAttribute, from: app, operation: "Finding the focused window")
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw WindowFailure.invalidValue("reference") }
        return value as! AXUIElement
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        let position = try read(kAXPositionAttribute, from: window, operation: "Reading window position")
        let size = try read(kAXSizeAttribute, from: window, operation: "Reading window size")
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw WindowFailure.invalidValue("frame")
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw WindowFailure.invalidValue("frame")
        }
        return CGRect(origin: point, size: dimensions)
    }

    func setFrame(_ frame: CGRect, on window: AXUIElement) throws {
        // Check both before moving, so a known non-resizable window is not partially changed.
        try requireSettable(kAXPositionAttribute, name: "position", on: window)
        try requireSettable(kAXSizeAttribute, name: "size", on: window)
        var point = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else {
            throw WindowFailure.invalidValue("target frame")
        }
        let moveResult = setAttribute(window, kAXPositionAttribute as CFString, position)
        guard moveResult == .success else { throw WindowFailure.accessibility("Moving the window", moveResult.rawValue) }
        let resizeResult = setAttribute(window, kAXSizeAttribute as CFString, dimensions)
        guard resizeResult == .success else { throw WindowFailure.partialResize(resizeResult.rawValue) }
    }

    private func read(_ attribute: String, from element: AXUIElement, operation: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = copyAttribute(element, attribute as CFString, &value)
        if attribute == kAXFocusedWindowAttribute && (result == .noValue || result == .attributeUnsupported || (result == .success && value == nil)) {
            throw WindowFailure.noWindow
        }
        guard result == .success else { throw WindowFailure.accessibility(operation, result.rawValue) }
        guard let value else { throw WindowFailure.invalidValue(attribute) }
        return value
    }

    private func requireSettable(_ attribute: String, name: String, on window: AXUIElement) throws {
        var settable: DarwinBoolean = false
        let result = isSettable(window, attribute as CFString, &settable)
        guard result == .success else { throw WindowFailure.accessibility("Checking window \(name)", result.rawValue) }
        guard settable.boolValue else { throw WindowFailure.notSettable(name) }
    }
}
