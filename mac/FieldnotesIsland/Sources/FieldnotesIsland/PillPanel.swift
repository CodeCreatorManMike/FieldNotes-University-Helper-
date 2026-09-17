import AppKit
import SwiftUI

/// The small always-visible anchor panel (see PillView). Docked at the
/// top-left corner; hidden only while the full IslandPanel is showing so
/// they don't overlap.
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

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 11
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(blur)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.contentView = container
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let size = contentView?.fittingSize ?? NSSize(width: 50, height: 26)
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.minX + 6, y: frame.maxY - size.height - 6, width: size.width, height: size.height), display: true)
    }
}
