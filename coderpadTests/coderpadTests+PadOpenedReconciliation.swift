//
//  coderpadTests+PadOpenedReconciliation.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad opened reconciliation")
struct PadOpenedReconciliationTests {
    @Test
    func `authoritative pad reconciliation keeps present records and identifies vanished pads`() {
        let opened = Date(timeIntervalSince1970: 1000)
        let entries = ["present": opened, "vanished": opened]

        let result = PadOpenedStore.reconciledOpenRecords(entries, presentPadIDs: ["present"])

        #expect(result.kept == ["present": opened])
        #expect(result.removedIDs == ["vanished"])
    }

    @Test
    func `empty authoritative list removes every recorded pad`() {
        let entries = ["one": Date(timeIntervalSince1970: 1), "two": Date(timeIntervalSince1970: 2)]

        let result = PadOpenedStore.reconciledOpenRecords(entries, presentPadIDs: [])

        #expect(result.kept.isEmpty)
        #expect(result.removedIDs == ["one", "two"])
    }
}
