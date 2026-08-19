@testable import CoderPadDesignSystem
import Testing

@Suite("Filter chip menu")
struct FilterChipMenuTests {
    @Test
    func `duplicate option identities retain only their first position`() {
        #expect(FilterChipMenu.uniqueOptions(["b", "a", "b", "c", "a"]) == ["b", "a", "c"])
    }
}
