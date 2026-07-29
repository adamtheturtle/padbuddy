import CoderPadToolCore
import Testing

@Test func `core validation is runnable`() {
    #expect(positiveID(1) == 1)
    #expect(positiveID(0) == nil)
}
