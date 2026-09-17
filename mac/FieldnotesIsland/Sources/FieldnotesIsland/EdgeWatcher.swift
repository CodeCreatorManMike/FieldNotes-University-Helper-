import AppKit

/// Polls the global mouse position (no Accessibility permission required,
/// unlike a global event monitor) and reports whether the pointer is
/// hovering the trigger zone at the top-left of the screen, or resting
/// over the island panel itself once it's shown.
final class EdgeWatcher {
    private var timer: Timer?
    private var outsideTicks = 0
    private let hideAfterTicks = 14 // ~1.1s of being away before hiding, avoids flicker

    var panelFrameProvider: (() -> CGRect?)?
    var pillFrameProvider: (() -> CGRect?)?
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private var isShown = false

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() { timer?.invalidate() }

    private func tick() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let loc = NSEvent.mouseLocation
        let frame = screen.frame
        // Trigger zone: a thin strip down the left edge, upper half of the screen.
        let inTriggerZone = (frame.maxX - loc.x) < 10 && loc.y > frame.minY + frame.height * 0.45
        let inPanel = panelFrameProvider?().map { NSMouseInRect(loc, $0.insetBy(dx: -6, dy: -6), false) } ?? false
        let inPill = pillFrameProvider?().map { NSMouseInRect(loc, $0.insetBy(dx: -6, dy: -6), false) } ?? false

        if inTriggerZone || inPanel || inPill {
            outsideTicks = 0
            if !isShown {
                isShown = true
                onShow?()
            }
        } else if isShown {
            outsideTicks += 1
            if outsideTicks >= hideAfterTicks {
                isShown = false
                outsideTicks = 0
                onHide?()
            }
        }
    }
}
