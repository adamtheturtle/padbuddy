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

    @Test
    func `full pagination stops ever-new offsets at its page cap`() async {
        do {
            _ = try await screenClient().listAllTests(campaignID: 888)
            Issue.record("Expected the Screen page cap to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("maximum page count"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `full pagination rejects an unseen backward offset`() async {
        do {
            _ = try await screenClient().listAllTests(campaignID: 889)
            Issue.record("Expected backward pagination to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("invalid next offset"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [
        "http://screen.example.com",
        "file:///tmp/screen",
        "https://user:password@screen.example.com",
        "https://screen.example.com/tenant",
        "https://screen.example.com?key=value",
        "https://screen.example.com/#fragment"
    ])
    func `unsafe base URLs are rejected before credentials are attached`(rawURL: String) async throws {
        let url = try #require(URL(string: rawURL))
        let client = ScreenClient(apiKey: "secret", baseURL: url, session: URLSession(configuration: .ephemeral))

        do {
            _ = try await client.listCampaigns()
            Issue.record("Expected an unsafe Screen base URL to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("credential-free HTTPS origin"))
        } catch {
            Issue.record("Unexpected error: \(error)")
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
