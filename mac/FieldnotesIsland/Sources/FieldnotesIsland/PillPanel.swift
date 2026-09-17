import AppKit
import SwiftUI

/// The always-visible anchor panel (see PillView). Docked at the top-left
/// corner; hidden only while the full IslandPanel is showing so they don't
/// overlap. Solid opaque white — deliberately NOT a vibrancy/blur material,
/// which blends with whatever's behind it and can end up nearly invisible
/// over a light desktop background. This has to be seen at a glance, always.
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

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 13
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.black.withAlphaComponent(0.1).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(card)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.contentView = container
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let size = contentView?.fittingSize ?? NSSize(width: 220, height: 44)
        let frame = screen.visibleFrame
        setFrame(NSRect(x: frame.minX + 8, y: frame.maxY - size.height - 8, width: size.width, height: size.height), display: true)
    }
}
