import AppGroupMailbox
@testable import PadBuddy
import Testing

@Suite("Widget cleanup claim finalization")
struct WidgetHandoffCleanupTests {
    private struct Failure: Error {}

    @Test func `transient finalization failures retry while permanent failures remain visible`() {
        var attempts = 0
        let recovered = WidgetSharedStore.completeHandoffCleanup(context: "test release") {
            attempts += 1
            if attempts < 3 {
                throw Failure()
            }
        }
        #expect(recovered)
        #expect(attempts == 3)
        let failed = WidgetSharedStore.completeHandoffCleanup(context: "test acknowledgement") { throw Failure() }
        #expect(!failed)
    }

    @Test func `a claim already finalized elsewhere needs no recovery`() {
        let completed = WidgetSharedStore.completeHandoffCleanup(context: "test completed claim") {
            throw AppGroupMailbox<WidgetPendingRequest>.MailboxError.claimNoLongerExists
        }
        #expect(completed)
    }
}
