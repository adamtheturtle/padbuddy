@testable import PadBuddy
import Testing

@Suite("Screen failure summaries")
struct ScreenActionFailureSummaryTests {
    @Test func `many failures retain only a fixed diagnostic sample and one total`() {
        var summary = ScreenActionFailureSummary()
        for id in 1 ... 10000 {
            summary.append(ScreenActionFailure(operation: "Delete", testID: id, candidate: "Ada",
                                               accountName: "Acme", reason: "Unavailable"))
        }
        #expect(summary.count == 10000)
        #expect(summary.samples.count == 8)
        #expect(summary.diagnostic.contains("#1"))
        #expect(!summary.diagnostic.contains("#9"))
        #expect(summary.diagnostic.unicodeScalars.count < 16000)
        summary.removeAll()
        #expect(summary.isEmpty)
        #expect(summary.samples.isEmpty)
        #expect(summary.diagnostic.isEmpty)
    }

    @Test func `repeated operation failures count without consuming the diagnostic sample`() {
        var summary = ScreenActionFailureSummary()
        let failure = ScreenActionFailure(operation: "Cancel", testID: 1, candidate: "Ada",
                                          accountName: nil, reason: "Unavailable")
        for _ in 1 ... 1000 {
            summary.append(failure)
        }
        #expect(summary.count == 1000)
        #expect(summary.samples.count == 1)
    }
}
