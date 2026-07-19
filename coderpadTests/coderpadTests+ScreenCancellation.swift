//
//  coderpadTests+ScreenCancellation.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen cancellation")
struct ScreenCancellationTests {
    @Test
    func `cancelled transport remains task cancellation`() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancelledScreenURLProtocol.self]
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: configuration))

        await #expect(throws: CancellationError.self) {
            _ = try await client.listCampaigns()
        }
    }
}

final nonisolated class CancelledScreenURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}
