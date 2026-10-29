import Foundation

/// The visible merged lists and directory share a small account fan-out budget.
@MainActor
enum MergedAccountFetch {
    static let maximumConcurrent = 3

    static func eligibleAccounts(_ accounts: [Account]) -> [Account] {
        var seen = Set<UUID>()
        return accounts.filter { $0.isInterviewFetchEligible && seen.insert($0.id).inserted }
    }

    static func results<Target: Sendable, Output: Sendable>(
        for targets: [Target],
        shouldContinue: () -> Bool,
        fetch: @escaping @Sendable (Target) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: Output.self) { group in
            var iterator = targets.makeIterator()
            func addNext() {
                guard !Task.isCancelled, shouldContinue(), let target = iterator.next() else { return }

                group.addTask { await fetch(target) }
            }
            for _ in 0 ..< maximumConcurrent {
                addNext()
            }
            var results: [Output] = []
            while let result = await group.next() {
                guard !Task.isCancelled, shouldContinue() else {
                    group.cancelAll()
                    break
                }

                results.append(result)
                addNext()
            }
            return results
        }
    }
}
