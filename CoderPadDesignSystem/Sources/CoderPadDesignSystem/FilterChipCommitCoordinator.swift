import Foundation

@MainActor
final class FilterChipCommitCoordinator {
    private var generation = 0
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func schedule(
        delay: Duration = .milliseconds(80),
        operation: @escaping @MainActor () -> Void
    ) {
        generation &+= 1
        let scheduledGeneration = generation
        task?.cancel()
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  scheduledGeneration == generation else { return }

            operation()
            task = nil
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
