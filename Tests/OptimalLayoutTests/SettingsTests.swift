import ServiceManagement
import Sparkle
import Testing
@testable import OptimalLayout

@MainActor
struct SettingsTests {
    private func model() -> SettingsModel {
        SettingsModel(updaterController: SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        ))
    }

    @Test func pendingLoginApprovalIsNotReportedAsEnabled() {
        let settings = model()
        for (status, text, requested) in [
            (SMAppService.Status.notRegistered, "Disabled", false),
            (.enabled, "Enabled", true),
            (.requiresApproval, "Approval required", true),
            (.notFound, "Unavailable", false)
        ] {
            settings.loginStatus = status
            #expect(settings.loginStatusText == text)
            #expect(settings.launchAtLogin == requested)
        }
    }

    @Test func diagnosticsPreserveIndependentFailures() {
        let settings = model()
        settings.accessibilityAllowed = false
        settings.loginStatus = .requiresApproval
        settings.loginError = "Registration failed"
        settings.problems = AppProblems(shortcutFailures: ["⌘⌥2 is unavailable"], windowFailure: "No focused window")
        let report = settings.diagnostics
        for detail in ["Accessibility: Not allowed", "Launch at Login: Approval required",
                       "Registration failed", "⌘⌥2 is unavailable", "No focused window"] {
            #expect(report.contains(detail))
        }
        settings.accessibilityAllowed = true
        settings.problems.windowFailure = nil
        #expect(settings.diagnostics.contains("Accessibility: Allowed"))
        #expect(settings.diagnostics.contains("⌘⌥2 is unavailable"))
        #expect(settings.diagnostics.contains("Last window command error: None recorded"))
    }
}
