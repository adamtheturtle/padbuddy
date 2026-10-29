import Foundation

/// Timed-out work keeps its permit until it actually finishes, bounding even
/// cancellation-ignoring requests across repeated navigation sessions.
@MainActor
final class NavigationWarmSlots {
    static let shared = NavigationWarmSlots(maximum: 4)
    private let maximum: Int
    private var owners = Set<UUID>()

    init(maximum: Int) {
        self.maximum = max(1, maximum)
    }

    func claim() -> UUID? {
        guard owners.count < maximum else { return nil }

        let owner = UUID()
        owners.insert(owner)
        return owner
    }

    func release(_ owner: UUID) {
        owners.remove(owner)
    }
}
