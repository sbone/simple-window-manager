import Carbon.HIToolbox
import Foundation

struct ShortcutFailure: Error, LocalizedError, Equatable {
    let shortcut: String
    let status: OSStatus

    var errorDescription: String? {
        if status == eventHotKeyExistsErr {
            return "\(shortcut) is already registered. Change or disable the conflicting shortcut in the other app, then restart OL. You can still use the menu command."
        }
        return "\(shortcut) could not be registered (macOS error \(status)). Restart OL and try again. You can still use the menu command."
    }
}

struct Shortcut: Sendable {
    static let signature: OSType = 0x4F4C0000
    static let all = [
        Shortcut(id: 1, keyCode: UInt32(kVK_ANSI_1)),
        Shortcut(id: 2, keyCode: UInt32(kVK_ANSI_2)),
        Shortcut(id: 3, keyCode: UInt32(kVK_ANSI_3)),
        Shortcut(id: 4, keyCode: UInt32(kVK_ANSI_4)),
        Shortcut(id: 0, keyCode: UInt32(kVK_ANSI_0))
    ]
    let id: UInt32
    let keyCode: UInt32
    var label: String { "⌘⌥\(id) (\(Layout(rawValue: id)?.title ?? "Switch Display"))" }

    @MainActor
    static func registerAll(using register: (Shortcut) throws -> EventHotKeyRef = { try $0.register() }) -> (references: [EventHotKeyRef], failures: [String]) {
        var references: [EventHotKeyRef] = []
        var failures: [String] = []
        for shortcut in all {
            do {
                references.append(try register(shortcut))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return (references, failures)
    }

    @MainActor
    func register(using registerHotKey: (UInt32, UInt32, EventHotKeyID, EventTargetRef?, OptionBits, UnsafeMutablePointer<EventHotKeyRef?>?) -> OSStatus = RegisterEventHotKey) throws -> EventHotKeyRef {
        var reference: EventHotKeyRef?
        let result = registerHotKey(keyCode, UInt32(cmdKey | optionKey), EventHotKeyID(signature: Self.signature, id: id),
                                    GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard result == noErr else { throw ShortcutFailure(shortcut: label, status: result) }
        guard let reference else { throw ShortcutFailure(shortcut: label, status: OSStatus(paramErr)) }
        return reference
    }
}

struct AppProblems {
    var shortcutFailures: [String] = []
    var windowFailure: String?

    var messages: [String] { shortcutFailures + (windowFailure.map { [$0] } ?? []) }
}
