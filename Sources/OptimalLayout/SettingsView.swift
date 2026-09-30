import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsModel
    @State private var canCheckForUpdates = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility") {
                    Label(settings.accessibilityAllowed ? "Allowed" : "Not allowed",
                          systemImage: settings.accessibilityAllowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(settings.accessibilityAllowed ? Color.green : Color.orange)
                }
                Text("Allows Optimal Layout to move and resize windows in other apps.")
                    .foregroundStyle(.secondary)
                Button("Open Accessibility Settings…", action: settings.openAccessibilitySettings)
                DisclosureGroup("Permission enabled, but commands still fail?") {
                    Text("Quit Optimal Layout, remove its entry in System Settings → Privacy & Security → Accessibility, then add this copy of the app again and reopen it. Quit any older copies of Optimal Layout first.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("Show This App in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Screen Recording and Input Monitoring are not required. Permission status is checked again when you return to the app.")
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                LabeledContent("Login status", value: settings.loginStatusText)
                if settings.loginStatus == .requiresApproval {
                    Text("Allow Optimal Layout in Login Items to finish enabling startup.")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…", action: SMAppService.openSystemSettingsLoginItems)
                } else if settings.loginStatus == .notFound {
                    Text("macOS could not find this login item. Move the app to Applications and reopen it, then try again.")
                        .foregroundStyle(.secondary)
                }
                if let error = settings.loginError {
                    Label("Launch at Login could not be changed: \(error)", systemImage: "exclamationmark.triangle")
                        .textSelection(.enabled)
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: settings.version)
                Toggle("Automatically Check for Updates", isOn: $settings.automaticallyChecksForUpdates)
                Button("Check for Updates…") { settings.updaterController.checkForUpdates(nil) }
                    .disabled(!canCheckForUpdates)
            }

            Section("Diagnostics") {
                LabeledContent("Keyboard shortcuts") {
                    Label(settings.problems.shortcutFailures.isEmpty ? "All registered" : "Conflicts or errors",
                          systemImage: settings.problems.shortcutFailures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                }
                ForEach(settings.problems.shortcutFailures, id: \.self) { failure in
                    Text(failure).textSelection(.enabled)
                }
                LabeledContent("Last window command error", value: settings.problems.windowFailure == nil ? "None recorded" : "Needs attention")
                if let failure = settings.problems.windowFailure {
                    Text(failure).textSelection(.enabled)
                }
                HStack {
                    Button("Refresh Status", action: settings.refresh)
                    Button("Copy Diagnostics", action: settings.copyDiagnostics)
                }
                Text("Copies the app version and location, macOS version, display count, statuses, and errors for a bug report.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: settings.refresh)
        .onReceive(settings.updaterController.updater.publisher(for: \.canCheckForUpdates)) {
            canCheckForUpdates = $0
        }
        .onReceive(settings.updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)) {
            settings.automaticallyChecksForUpdates = $0
        }
        .frame(minWidth: 520, minHeight: 540)
    }
}
