import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import Sparkle

@MainActor
@Observable
final class SettingsModel {
    var accessibilityAllowed = false
    var loginStatus: SMAppService.Status = .notRegistered
    var loginError: String?
    var problems = AppProblems()
    var automaticallyChecksForUpdates = false {
        didSet {
            if updaterController.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
        }
    }
    let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
    }

    var launchAtLogin: Bool {
        get { loginStatus == .enabled || loginStatus == .requiresApproval }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
            refresh()
        }
    }

    var loginStatusText: String {
        switch loginStatus {
        case .enabled: "Enabled"
        case .notRegistered: "Disabled"
        case .requiresApproval: "Approval required"
        case .notFound: "Unavailable"
        @unknown default: "Unknown"
        }
    }

    func refresh() {
        accessibilityAllowed = AXIsProcessTrusted()
        loginStatus = SMAppService.mainApp.status
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    func openAccessibilitySettings() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "Development") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    var diagnostics: String {
        """
        Optimal Layout \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App: \(Bundle.main.bundleURL.path)
        Accessibility: \(accessibilityAllowed ? "Allowed" : "Not allowed")
        Launch at Login: \(loginStatusText)
        Launch at Login error: \(loginError ?? "None")
        Automatic update checks: \(automaticallyChecksForUpdates ? "Enabled" : "Disabled")
        Displays: \(NSScreen.screens.count)
        Shortcuts: \(problems.shortcutFailures.isEmpty ? "All registered" : problems.shortcutFailures.joined(separator: "\n"))
        Last window command error: \(problems.windowFailure ?? "None recorded")
        """
    }

    func copyDiagnostics() {
        refresh()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}
