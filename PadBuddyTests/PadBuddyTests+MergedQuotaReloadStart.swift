//
//  PadBuddyTests+MergedQuotaReloadStart.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Merged quota reload start")
struct MergedQuotaReloadStartTests {
    @Test func `an empty reload still claims a newer generation`() {
        #expect(MergedQuotaReloadStart.claim(after: 7, hasTargets: false)
            == MergedQuotaReloadStart(generation: 8, isLoading: false))
    }

    @Test func `a reload with targets claims its loading state`() {
        #expect(MergedQuotaReloadStart.claim(after: 7, hasTargets: true)
            == MergedQuotaReloadStart(generation: 8, isLoading: true))
    }
}
