//
//  coderpadTests+AccountScopeProbes.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Account scope probes")
@MainActor
struct AccountScopeProbeTests {
    private enum ProbeFailure: Error {
        case transient
    }

    @Test
    func `probe results distinguish authorization refusal and uncertainty`() async {
        let authorized = await AccountEditor.scopeProbeResult {}
        let refused = await AccountEditor.scopeProbeResult {
            throw CoderPadError.http(403, "Forbidden")
        }
        let unknown = await AccountEditor.scopeProbeResult { throw ProbeFailure.transient }

        #expect(authorized == .authorized)
        #expect(refused == .refused)
        #expect(unknown == .unknown)
    }

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
