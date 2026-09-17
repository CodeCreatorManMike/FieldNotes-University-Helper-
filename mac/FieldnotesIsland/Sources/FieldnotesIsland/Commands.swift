import AppKit

/// Shared entry points the SwiftUI context menu (built with no reference to
/// AppDelegate) calls into.
enum Commands {
    static var refresh: () -> Void = {}
    static var togglePanel: () -> Void = {}

    static func quit() { NSApp.terminate(nil) }
    static func toggleLogin() { LaunchAtLogin.toggle() }
}
