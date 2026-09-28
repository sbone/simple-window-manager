import ApplicationServices
import Carbon.HIToolbox
import Foundation
import Testing
@testable import OptimalLayout

@MainActor
struct FailureTests {
    // Only an opaque handle: every Accessibility read/write below is intercepted.
    let window = AXUIElementCreateApplication(12345)
    let target = CGRect(x: 100, y: 200, width: 600, height: 400)

    @Test func missingApplicationDoesNotQueryAccessibility() {
        var access = WindowAccess()
        access.copyAttribute = { _, _, _ in
            Issue.record("No API call should be made without an active application")
            return .failure
        }
        #expect(throws: WindowFailure.noApplication) { try access.focusedWindow(processIdentifier: nil) }
    }

    @Test(arguments: [AXError.noValue, .attributeUnsupported, .success])
    func absentFocusedWindowIsReported(status: AXError) {
        var access = WindowAccess()
        access.copyAttribute = { _, _, _ in status }
        #expect(throws: WindowFailure.noWindow) { try access.focusedWindow(processIdentifier: 12345) }
    }

    @Test(arguments: [AXError.apiDisabled, .cannotComplete, .invalidUIElement])
    func focusedWindowAPIFailuresArePreserved(status: AXError) {
        var access = WindowAccess()
        access.copyAttribute = { _, _, _ in status }
        #expect(throws: WindowFailure.accessibility("Finding the focused window", status.rawValue)) {
            try access.focusedWindow(processIdentifier: 12345)
        }
    }

    @Test func focusedWindowRejectsWrongTypeAndAcceptsWindowHandle() throws {
        var access = WindowAccess()
        access.copyAttribute = { _, _, output in
            output.pointee = "not a window" as CFString
            return .success
        }
        #expect(throws: WindowFailure.invalidValue("reference")) { try access.focusedWindow(processIdentifier: 12345) }
        access.copyAttribute = { _, _, output in
            output.pointee = window
            return .success
        }
        let found = try access.focusedWindow(processIdentifier: 12345)
        #expect(CFEqual(found, window))
    }

    @Test func frameReadPreservesGeometryAndReportsReadFailure() throws {
        var access = accessReturningFrame(target)
        #expect(try access.frame(of: window) == target)
        let originalRead = access.copyAttribute
        access.copyAttribute = { element, attribute, output in
            if attribute as String == kAXSizeAttribute { return .cannotComplete }
            return originalRead(element, attribute, output)
        }
        #expect(throws: WindowFailure.accessibility("Reading window size", AXError.cannotComplete.rawValue)) {
            try access.frame(of: window)
        }
    }

    @Test func malformedFramesNeverBecomeZeroGeometry() {
        var access = WindowAccess()
        access.copyAttribute = { _, _, output in
            output.pointee = "invalid frame" as CFString
            return .success
        }
        #expect(throws: WindowFailure.invalidValue("frame")) { try access.frame(of: window) }

        for frame in [CGRect(x: 0, y: 0, width: 0, height: 100),
                      CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)] {
            let invalid = accessReturningFrame(frame)
            #expect(throws: WindowFailure.invalidValue("frame")) { try invalid.frame(of: window) }
        }

        access.copyAttribute = { _, _, output in
            var point = CGPoint.zero
            output.pointee = AXValueCreate(.cgPoint, &point) // Wrong AXValue subtype for size.
            return .success
        }
        #expect(throws: WindowFailure.invalidValue("frame")) { try access.frame(of: window) }
    }

    @Test func unsupportedResizeIsDetectedBeforeAnyMovement() {
        var writes = 0
        var access = writableAccess()
        access.isSettable = { _, attribute, output in
            output.pointee = DarwinBoolean(attribute as String != kAXSizeAttribute)
            return .success
        }
        access.setAttribute = { _, _, _ in writes += 1; return .success }
        #expect(throws: WindowFailure.notSettable("size")) { try access.setFrame(target, on: window) }
        #expect(writes == 0)
    }

    @Test func permissionFailureDuringPreflightPreventsWrites() {
        var writes = 0
        var access = writableAccess()
        access.isSettable = { _, _, _ in .apiDisabled }
        access.setAttribute = { _, _, _ in writes += 1; return .success }
        #expect(throws: WindowFailure.accessibility("Checking window position", AXError.apiDisabled.rawValue)) {
            try access.setFrame(target, on: window)
        }
        #expect(writes == 0)
    }

    @Test func failedMoveStopsBeforeResize() {
        var writes: [String] = []
        var access = writableAccess()
        access.setAttribute = { _, attribute, _ in
            writes.append(attribute as String)
            return .cannotComplete
        }
        #expect(throws: WindowFailure.accessibility("Moving the window", AXError.cannotComplete.rawValue)) {
            try access.setFrame(target, on: window)
        }
        #expect(writes == [kAXPositionAttribute])
    }

    @Test func failedResizeReportsPartialMovement() {
        var writes: [String] = []
        var access = writableAccess()
        access.setAttribute = { _, attribute, _ in
            writes.append(attribute as String)
            return attribute as String == kAXSizeAttribute ? .cannotComplete : .success
        }
        #expect(throws: WindowFailure.partialResize(AXError.cannotComplete.rawValue)) {
            try access.setFrame(target, on: window)
        }
        #expect(writes == [kAXPositionAttribute, kAXSizeAttribute])
    }

    @Test func successfulWriteSendsCorrectAXValues() throws {
        var writes: [String] = []
        var access = writableAccess()
        access.setAttribute = { _, attribute, value in
            writes.append(attribute as String)
            if attribute as String == kAXPositionAttribute {
                var point = CGPoint.zero
                #expect(AXValueGetValue(value as! AXValue, .cgPoint, &point))
                #expect(point == target.origin)
            } else {
                var size = CGSize.zero
                #expect(AXValueGetValue(value as! AXValue, .cgSize, &size))
                #expect(size == target.size)
            }
            return .success
        }
        try access.setFrame(target, on: window)
        #expect(writes == [kAXPositionAttribute, kAXSizeAttribute])
    }

    @Test func failedLayoutDoesNotAdvanceCycle() throws {
        var geometry = WindowGeometry()
        let usable = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(throws: WindowFailure.notSettable("size")) {
            try geometry.apply(.two, usable: usable) { _ in throw WindowFailure.notSettable("size") }
        }
        var access = writableAccess()
        access.setAttribute = { _, _, _ in .success }
        try geometry.apply(.two, usable: usable) { frame in
            #expect(frame == CGRect(x: 0, y: 0, width: 500, height: 800))
            try access.setFrame(frame, on: window)
        }
        geometry.apply(.two, usable: usable) { frame in
            #expect(frame == CGRect(x: 500, y: 0, width: 500, height: 800))
        }
    }

    @Test func conflictingShortcutReportsExactCombinationAndContinuesOtherRegistrations() {
        var registered: [UInt32] = []
        let result = Shortcut.registerAll { shortcut in
            try shortcut.register { keyCode, modifiers, id, _, options, reference in
                #expect(keyCode == shortcut.keyCode)
                #expect(modifiers == UInt32(cmdKey | optionKey))
                #expect(id.signature == Shortcut.signature)
                #expect(options == OptionBits(kEventHotKeyExclusive))
                if id.id == 2 { return OSStatus(eventHotKeyExistsErr) }
                registered.append(id.id)
                reference?.pointee = OpaquePointer(bitPattern: 1)
                return noErr
            }
        }
        #expect(registered == [1, 3, 4, 0])
        #expect(result.references.count == 4)
        #expect(result.failures == [ShortcutFailure(shortcut: "⌘⌥2 (Layout 2)", status: OSStatus(eventHotKeyExistsErr)).localizedDescription])
        #expect(result.failures.first?.contains("already registered") == true)
    }

    @Test func unexpectedRegistrationFailureAndMissingHandleAreErrors() {
        let shortcut = Shortcut.all[0]
        #expect(throws: ShortcutFailure(shortcut: shortcut.label, status: OSStatus(paramErr))) {
            try shortcut.register { _, _, _, _, _, _ in OSStatus(paramErr) }
        }
        #expect(throws: ShortcutFailure(shortcut: shortcut.label, status: OSStatus(paramErr))) {
            try shortcut.register { _, _, _, _, _, _ in noErr }
        }
    }

    @Test func successfulWindowCommandDoesNotClearShortcutProblems() {
        var problems = AppProblems(shortcutFailures: ["⌘⌥2 is unavailable"], windowFailure: "No focused window")
        #expect(problems.messages.count == 2)
        problems.windowFailure = nil
        #expect(problems.messages == ["⌘⌥2 is unavailable"])
        problems.shortcutFailures = []
        #expect(problems.messages.isEmpty)
    }

    private func writableAccess() -> WindowAccess {
        var access = WindowAccess()
        access.isSettable = { _, _, output in output.pointee = true; return .success }
        return access
    }

    private func accessReturningFrame(_ frame: CGRect) -> WindowAccess {
        var access = WindowAccess()
        access.copyAttribute = { _, attribute, output in
            if attribute as String == kAXPositionAttribute {
                var point = frame.origin
                output.pointee = AXValueCreate(.cgPoint, &point)
            } else {
                var size = frame.size
                output.pointee = AXValueCreate(.cgSize, &size)
            }
            return .success
        }
        return access
    }
}
