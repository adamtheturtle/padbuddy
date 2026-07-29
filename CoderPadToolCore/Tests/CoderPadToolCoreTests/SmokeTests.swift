import CoderPadToolCore
import Testing

@Test func `core validation is runnable`() {
    #expect(positiveID(1) == 1)
    #expect(positiveID(0) == nil)
}

@Test func `aggregate fields ignore surrounding whitespace`() {
    #expect(aggregateField(for: " owner ") == "owner_email")
    #expect(questionAggregateField(for: "\n language\t") == "language")
}

@Test func `pad filter echo matches applied filters`() {
    #expect(filtersEcho(owner: "  ", state: "\nstarted ", language: " Swift ") as? [String: String] == [
        "state": "started",
        "language": "Swift"
    ])
}

@Test func `question filter echo matches applied filters`() {
    let filters = questionFiltersEcho(owner: " ", author: "\nAda ", language: "\t", type: " live ")
    #expect(filters as? [String: String] == ["author": "Ada", "type": "live"])
}
