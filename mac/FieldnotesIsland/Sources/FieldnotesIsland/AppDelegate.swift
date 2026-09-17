import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var panel: IslandPanel!
    let watcher = EdgeWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — a pure edge-hover island
        panel = IslandPanel(state: state)
        state.start()

        watcher.panelFrameProvider = { [weak self] in self?.panel.isVisible == true ? self?.panel.frame : nil }
        watcher.onShow = { [weak self] in
            guard let self else { return }
            self.state.isPanelVisible = true
            self.state.refresh()
            self.panel.fadeIn()
        }
        watcher.onHide = { [weak self] in
            self?.state.isPanelVisible = false
            self?.panel.fadeOut()
        }
        watcher.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
