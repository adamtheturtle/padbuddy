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

    @Test
    func `HTTP errors retain only a bounded response-body prefix`() async {
        do {
            _ = try await screenClient().getTest(id: 999_999)
            Issue.record("Expected the mock server error")
        } catch let CoderPadError.http(code, body) {
            #expect(code == 451)
            #expect(body.utf8.count <= ScreenClient.maximumErrorBodyBytes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `a loose PDF-like media type is rejected`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().testReport(id: 424_243)
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
