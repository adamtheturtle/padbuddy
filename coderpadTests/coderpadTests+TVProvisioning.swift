@testable import CoderPad
import Foundation
import Testing

@Suite("TV provisioning links")
struct TVProvisioningTests {
    @Test func `accepts an HTTPS CoderPad provisioning link`() throws {
        let url = try #require(URL(string: "coderpad://provision?server=https%3A%2F%2Fapp.coderpad.io&apiKey=secret"))
        let request = try #require(TVProvisioningRequest(url: url))
        #expect(request.server == URL(string: "https://app.coderpad.io"))
        #expect(request.apiKey == "secret")
    }

    @Test func `rejects insecure servers and credentials in server URLs`() {
        let insecure = URL(string: "coderpad://provision?server=http%3A%2F%2Fexample.com&apiKey=x")!
        let credentials = URL(string: "coderpad://provision?server=https%3A%2F%2Fu%3Ap%40example.com&apiKey=x")!
        #expect(TVProvisioningRequest(url: insecure) == nil)
        #expect(TVProvisioningRequest(url: credentials) == nil)
    }

    @Test func `rejects blank keys and unrelated links`() {
        let blankKey = URL(string: "coderpad://provision?server=https%3A%2F%2Fexample.com&apiKey=%20")!
        #expect(TVProvisioningRequest(url: blankKey) == nil)
        #expect(TVProvisioningRequest(url: URL(string: "coderpad://pads")!) == nil)
    }
}
