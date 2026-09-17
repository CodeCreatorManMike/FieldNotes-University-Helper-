import Foundation
import ServiceManagement

/// Wraps SMAppService (macOS 13+). Only works when running from a properly
/// registered .app bundle (see build.sh) — a loose binary via `swift run`
/// will throw, which is caught and surfaced as a no-op rather than a crash.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // No .app bundle / not registered with Launch Services — ignore.
        }
    }
}
