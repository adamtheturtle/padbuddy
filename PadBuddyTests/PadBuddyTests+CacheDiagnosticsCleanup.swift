//
//  PadBuddyTests+CacheDiagnosticsCleanup.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Cache diagnostics account cleanup")
struct CacheLoadDiagnosticsAccountCleanupTests {
    @Test func `clearing an account drops every recorded kind`() {
        let account = UUID()
        CacheLoadDiagnostics.recordFailure(kind: "pads", account: account)
        CacheLoadDiagnostics.recordFailure(kind: "questions", account: account)
        CacheLoadDiagnostics.recordFailure(kind: "directory", account: account)

        CacheLoadDiagnostics.clear(account: account)

        #expect(CacheLoadDiagnostics.failedKinds(account: account).isEmpty)
    }

    @Test func `an unknown kind is not retained`() {
        let account = UUID()

        CacheLoadDiagnostics.recordFailure(kind: "not-a-cache-kind", account: account)

        #expect(CacheLoadDiagnostics.failedKinds(account: account).isEmpty)
        CacheLoadDiagnostics.clear(account: account)
    }
}
