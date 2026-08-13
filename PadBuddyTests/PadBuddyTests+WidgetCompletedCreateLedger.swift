//
//  PadBuddyTests+WidgetCompletedCreateLedger.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Widget completed-create ledger", .serialized)
struct WidgetCompletedCreateLedgerTests {
    private func defaults() throws -> UserDefaults {
        let suite = "WidgetCompletedCreateLedgerTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test func `recovered completed request does not create again`() throws {
        let defaults = try defaults()
        let id = UUID()
        #expect(WidgetCompletedCreateLedger.shouldCreate(id, defaults: defaults))

        #expect(WidgetCompletedCreateLedger.recordCompleted(id, defaults: defaults))

        #expect(!WidgetCompletedCreateLedger.shouldCreate(id, defaults: defaults))
    }

    @Test func `distinct request identities remain independent`() throws {
        let defaults = try defaults()
        let first = UUID()
        let second = UUID()

        #expect(WidgetCompletedCreateLedger.recordCompleted(first, defaults: defaults))
        #expect(!WidgetCompletedCreateLedger.shouldCreate(first, defaults: defaults))
        #expect(WidgetCompletedCreateLedger.shouldCreate(second, defaults: defaults))
    }
}
