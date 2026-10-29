import Foundation
@testable import PadBuddy
import Testing

@Suite("Late Spotlight acknowledgements")
struct SpotlightLateCallbackTests {
    @Test func `obsolete generations and removed accounts cannot restore fingerprints`() {
        let account = UUID(), identifier = "pad:\(account.uuidString):ABC123"
        let record = SpotlightIndexer.PadIndexRecord(identifier: identifier, title: "Pad", description: "Active")
        let generation = SpotlightIndexer.currentClearGeneration()
        defer {
            SpotlightIndexer.enrichmentLock.withLock {
                SpotlightIndexer.removedAccounts.remove(account)
                SpotlightIndexer.indexedPadFingerprints.removeValue(forKey: identifier)
            }
        }
        SpotlightIndexer.acknowledgePadRecords([record], generation: generation - 1, account: account)
        #expect(SpotlightIndexer.changedPadRecords([record]).count == 1)
        SpotlightIndexer.enrichmentLock.withLock { _ = SpotlightIndexer.removedAccounts.insert(account) }
        SpotlightIndexer.acknowledgePadRecords([record], generation: generation, account: account)
        #expect(SpotlightIndexer.changedPadRecords([record]).count == 1)
    }
}
