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
