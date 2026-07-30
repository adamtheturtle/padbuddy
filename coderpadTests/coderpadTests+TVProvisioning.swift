@testable import CoderPad
import Foundation
import Testing

@Suite("Companion provisioning payloads")
struct TVProvisioningTests {
    @Test func `accepts an HTTPS nearby-device payload`() throws {
        let request = try #require(TVProvisioningRequest(dictionary: [
            "server": "https://app.coderpad.io",
            "apiKey": "secret"
        ]))
        #expect(request.server == URL(string: "https://app.coderpad.io"))
        #expect(request.apiKey == "secret")
    }

    @Test func `rejects insecure servers and credentials in server URLs`() {
        #expect(TVProvisioningRequest(dictionary: ["server": "http://example.com", "apiKey": "x"]) == nil)
        #expect(TVProvisioningRequest(dictionary: ["server": "https://u:p@example.com", "apiKey": "x"]) == nil)
    }

    @Test func `rejects blank keys and missing payload fields`() {
        #expect(TVProvisioningRequest(dictionary: ["server": "https://example.com", "apiKey": " "]) == nil)
        #expect(TVProvisioningRequest(dictionary: ["server": "https://example.com"]) == nil)
    }
}
