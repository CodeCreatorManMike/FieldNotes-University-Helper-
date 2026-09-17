import Foundation
import Combine

/// A real 25-minute focus countdown (Pomodoro-style), not just a visual
/// mockup of one. Ticks every second while running; posts a notification
/// on completion via Notifier.
final class FocusTimer: ObservableObject {
    let total = 25 * 60
    @Published var remaining = 25 * 60
    @Published var isRunning = false

    private var timer: Timer?

    var label: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var progress: Double { 1 - Double(remaining) / Double(total) }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remaining = total
    }

    private func tick() {
        if remaining > 0 {
            remaining -= 1
        } else {
            pause()
            Notifier.shared.sendFocusComplete()
            remaining = total
        }
    }
}
