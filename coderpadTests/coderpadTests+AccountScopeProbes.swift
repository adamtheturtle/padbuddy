//
//  coderpadTests+AccountScopeProbes.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Account scope probes")
@MainActor
struct AccountScopeProbeTests {
    @Test
    func `an empty stream is not proof of endpoint access`() async {
        let stream = AsyncThrowingStream<[Int], any Error> { $0.finish() }

        await #expect(throws: AccountEditor.ScopeProbeError.self) {
            try await AccountEditor.requireFirstPage(stream)
        }
    }

    @Test
    func `one yielded page proves endpoint access`() async throws {
        let stream = AsyncThrowingStream<[Int], any Error> { continuation in
            continuation.yield([])
            continuation.finish()
        }

        try await AccountEditor.requireFirstPage(stream)
    }
}
