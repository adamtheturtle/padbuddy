@testable import CoderPadDesignSystem
import Testing

@Suite("Filter chip menu")
struct FilterChipMenuTests {
    @Test
    func `dismissing during delayed commit prevents the binding write`() async throws {
        let coordinator = FilterChipCommitCoordinator()
        var committed = false
        coordinator.schedule(delay: .milliseconds(20)) {
            committed = true
        }

        coordinator.cancel()
        try await Task.sleep(for: .milliseconds(40))

        #expect(!committed)
    }

    @Test
    func `duplicate option identities retain only their first position`() {
        #expect(FilterChipMenu.uniqueOptions(["b", "a", "b", "c", "a"]) == ["b", "a", "c"])
    }
}
