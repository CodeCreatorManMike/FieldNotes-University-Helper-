import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var panel: IslandPanel!
    var pill: PillPanel!
    let watcher = EdgeWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — a pure edge-hover island
        panel = IslandPanel(state: state)
        pill = PillPanel(state: state)
        state.start()
        Notifier.shared.requestAuthorization()

        Commands.refresh = { [weak self] in self?.state.refresh() }
        Commands.togglePanel = { [weak self] in self?.showPanel() }

        pill.reposition()
        pill.orderFrontRegardless()

        watcher.panelFrameProvider = { [weak self] in self?.panel.isVisible == true ? self?.panel.frame : nil }
        watcher.pillFrameProvider = { [weak self] in self?.pill.isVisible == true ? self?.pill.frame : nil }
        watcher.onShow = { [weak self] in self?.showPanel() }
        watcher.onHide = { [weak self] in self?.hidePanel() }
        watcher.start()
    }

    private func showPanel() {
        state.isPanelVisible = true
        state.refresh()
        pill.orderOut(nil)
        panel.fadeIn()
    }

    private func hidePanel() {
        state.isPanelVisible = false
        panel.fadeOut()
        pill.reposition()
        pill.orderFrontRegardless()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
