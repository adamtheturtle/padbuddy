//
//  TopRowPersistenceDebouncer.swift
//  PadBuddy
//

import Foundation

@MainActor
final class TopRowPersistenceDebouncer {
    private var task: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?
    private var pendingRestorationGeneration = 0
    private var generation = 0

    deinit {
        task?.cancel()
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pendingAction = action
        pendingRestorationGeneration = AppStateRestorationReset.generation
        generation += 1
        guard task == nil else { return }

        task = Task { @MainActor in
            var observedGeneration = generation
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }

                if observedGeneration != generation {
                    observedGeneration = generation
                    continue
                }

                flush()
                return
            }
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        let action = pendingAction
        let restorationGeneration = pendingRestorationGeneration
        pendingAction = nil
        guard restorationGeneration == AppStateRestorationReset.generation else { return }

        action?()
    }
}
