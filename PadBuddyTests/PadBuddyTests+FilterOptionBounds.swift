@testable import PadBuddy
import Testing

@Suite("Filter option input bounds")
struct FilterOptionBoundsTests {
    @Test func `oversized and control bearing identities do not become filter options`() {
        let huge = String(repeating: "x", count: 1_000_000)
        #expect(FilterOptionValues.boundedLanguages([huge, " PyThOn3 ", "python3", "bad\u{202e}"]) == ["python3"])
        #expect(FilterOptionValues.boundedOwners([huge, "person@coderpad.io", "bad\nemail"]) == ["person@coderpad.io"])
    }

    @Test func `distinct filter option collections have a fixed maximum`() {
        let values = (0 ..< 1000).map { "value\($0)" }
        #expect(
            FilterOptionValues.boundedLanguages(values.map(Optional.some)).count == FilterOptionValues.maximumOptions
        )
        #expect(FilterOptionValues.boundedOwners(values).count == FilterOptionValues.maximumOptions)
    }
}
