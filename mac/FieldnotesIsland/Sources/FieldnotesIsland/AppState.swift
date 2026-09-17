import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var next: NextPayload?
    @Published var isReachable = true
    @Published var isPanelVisible = false
    @Published var isBusy = false

    private var timer: Timer?

    var urgency: Urgency {
        guard let reasons = next?.top?.reason.joined(separator: " ") else { return .none }
        if reasons.contains("deadline has passed") || reasons.contains("is due in 0 day") { return .critical }
        if reasons.contains("is due in 1 day") || reasons.contains("is due in 2 day") { return .soon }
        return .normal
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        Task {
            do {
                let payload = try await FieldnotesAPI.fetchNext()
                DispatchQueue.main.async {
                    let previous = self.next
                    self.next = payload
                    self.isReachable = true
                    Notifier.shared.consider(previous: previous, current: payload)
                }
            } catch {
                DispatchQueue.main.async { self.isReachable = false }
            }
        }
    }

    func snoozeTop() {
        guard let id = next?.top?.id else { return }
        runAction {
            let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400)).prefix(10)
            try await FieldnotesAPI.patchProgress(id, ["snoozed": String(until)])
        }
    }

    func markTopKnown() {
        guard let id = next?.top?.id else { return }
        runAction {
            try await FieldnotesAPI.patchProgress(id, ["known": true])
        }
    }

    func addTask(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        runAction {
            let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
            try await FieldnotesAPI.addTask(text: text, date: String(today))
        }
    }

    private func runAction(_ action: @escaping () async throws -> Void) {
        isBusy = true
        Task {
            defer { DispatchQueue.main.async { self.isBusy = false } }
            do { try await action() } catch { /* surfaced only via isReachable on next poll */ }
            self.refresh()
        }
    }
}

enum Urgency {
    case none, normal, soon, critical

    var color: (Double, Double, Double) {
        switch self {
        case .none: return (0.55, 0.6, 0.65)
        case .normal: return (0.435, 0.827, 0.690)
        case .soon: return (0.98, 0.75, 0.3)
        case .critical: return (0.95, 0.35, 0.35)
        }
    }
}
