import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var next: NextPayload?
    @Published var isReachable = true
    @Published var isPanelVisible = false

    private var timer: Timer?

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
                    self.next = payload
                    self.isReachable = true
                }
            } catch {
                DispatchQueue.main.async { self.isReachable = false }
            }
        }
    }
}
