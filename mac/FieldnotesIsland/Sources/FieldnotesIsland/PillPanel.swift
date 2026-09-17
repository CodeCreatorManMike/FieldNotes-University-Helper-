import AppKit
import SwiftUI

/// The always-visible idle anchor (see PillView) — a small ring, not a
/// card, so the panel itself stays fully transparent; the ring's own black
/// disc + stroke give it contrast against any backdrop without needing an
/// opaque background window. Docked at the top-left corner; hidden only
/// while the full IslandPanel is showing so they don't overlap.
final class PillPanel: NSPanel {
    init(state: AppState) {
        let hosting = NSHostingView(rootView: PillView().environmentObject(state))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        self.contentView = hosting
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let size = contentView?.fittingSize ?? NSSize(width: 62, height: 62)
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.minX + 4, y: frame.maxY - size.height - 4, width: size.width, height: size.height), display: true)
    }
}
