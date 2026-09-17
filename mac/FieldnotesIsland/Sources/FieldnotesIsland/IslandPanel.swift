import AppKit
import SwiftUI

/// Borderless, non-activating floating panel: solid opaque black (not a
/// vibrancy material — that blends with whatever's behind it and can wash
/// out or vanish depending on backdrop) with continuous rounded corners,
/// sized to its SwiftUI content and pinned to the top-left of the screen.
final class IslandPanel: NSPanel {
    init(state: AppState) {
        let hosting = NSHostingView(rootView: IslandView().environmentObject(state))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.cgColor
        card.layer?.cornerRadius = 20
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
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
        let size = contentView?.fittingSize ?? NSSize(width: 300, height: 460)
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.maxX - size.width - 10, y: frame.maxY - size.height - 10)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func fadeIn() {
        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}
