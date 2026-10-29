import Foundation

/// Ownership of one detail view's report request, claimed before scheduling work.
nonisolated struct ScreenReportRequest {
    private var token: UUID?

    var isActive: Bool {
        token != nil
    }

    mutating func claim() -> UUID? {
        guard token == nil else { return nil }

        let claim = UUID()
        token = claim
        return claim
    }

    func isCurrent(_ claim: UUID) -> Bool {
        token == claim
    }

    mutating func finish(_ claim: UUID) {
        guard isCurrent(claim) else { return }

        token = nil
    }

    mutating func cancel() {
        token = nil
    }
}
