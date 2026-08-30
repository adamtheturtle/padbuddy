@testable import PadBuddy
import Testing

@Suite("Deletion cleanup retry policy")
struct DeletionCleanupRetryPolicyTests {
    @Test func `unresolved deletions wait only while a cache warm is active`() {
        #expect(DeletionCleanup.shouldRetryUnresolvedDeletion(cacheWarmInFlight: [false, true]))
        #expect(!DeletionCleanup.shouldRetryUnresolvedDeletion(cacheWarmInFlight: [false, false]))
        #expect(!DeletionCleanup.shouldRetryUnresolvedDeletion(cacheWarmInFlight: []))
    }

    @Test func `a resident holder cannot make partially warmed ownership authoritative`() {
        let residentHolderExists = true
        let shouldResolveResidentHolder = residentHolderExists
            && !DeletionCleanup.requiresCacheConsultationBeforeResolving(cacheReadiness: [true, false])

        #expect(!shouldResolveResidentHolder)
    }
}
