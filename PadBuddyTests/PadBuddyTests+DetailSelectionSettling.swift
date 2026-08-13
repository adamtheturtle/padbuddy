//
//  PadBuddyTests+DetailSelectionSettling.swift
//  PadBuddyTests
//

import Foundation
import Testing
@testable import PadBuddy

@Suite("Detail selection settling")
struct DetailSelectionSettlingTests {
    private struct WaitFailure: Error {}

    @Test func `cancellation remains cancellation`() async {
        await #expect(throws: CancellationError.self) {
            try await DetailSelectionSettling.wait(for: .zero) { _ in throw CancellationError() }
        }
    }

    @Test func `unexpected sleep failure remains observable`() async {
        await #expect(throws: WaitFailure.self) {
            try await DetailSelectionSettling.wait(for: .zero) { _ in throw WaitFailure() }
        }
    }
}
