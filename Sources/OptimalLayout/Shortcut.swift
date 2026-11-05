import Carbon.HIToolbox
import Foundation

struct ShortcutFailure: Error, LocalizedError, Equatable {
    let shortcut: String
    let status: OSStatus

    var errorDescription: String? {
        if status == eventHotKeyExistsErr {
            return "\(shortcut) is already registered, so this copy of Optimal Layout could not register it."
        }
        return "\(shortcut) could not be registered (macOS error \(status)). Choose Retry Shortcuts to try again. You can still use the menu command."
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
    var label: String { "⌘⌥\(id) (\(Layout(rawValue: id)?.title ?? "Move to Next Display"))" }

    @MainActor
    static func registerAll(keeping existing: [UInt32: EventHotKeyRef] = [:], using register: (Shortcut) throws -> EventHotKeyRef = { try $0.register() }) -> (references: [UInt32: EventHotKeyRef], failures: [String]) {
        var references = existing
        var failures: [String] = []
        for shortcut in all where references[shortcut.id] == nil {
            do {
                references[shortcut.id] = try register(shortcut)
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
    var otherRunningCopies: [String] = []

    var shortcutMessages: [String] {
        guard !shortcutFailures.isEmpty else { return [] }
        var messages = shortcutFailures
        messages.append("macOS does not tell Optimal Layout which app owns a shortcut. If these shortcuts still move windows, another running copy of Optimal Layout or another window manager may be handling them. Menu commands remain available.")
        if !otherRunningCopies.isEmpty {
            messages.append("Other running copies of Optimal Layout (possible conflicts):\n" + otherRunningCopies.joined(separator: "\n"))
        }
        messages.append("Quit other copies of Optimal Layout first. If needed, quit other shortcut apps one at a time and choose Retry Shortcuts to check whether the shortcut becomes available.")
        return messages
    }

    var messages: [String] { shortcutMessages + (windowFailure.map { [$0] } ?? []) }
}
