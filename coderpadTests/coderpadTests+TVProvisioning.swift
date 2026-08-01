@testable import CoderPad
import Foundation
import Testing

@Suite("Companion provisioning payloads")
struct TVProvisioningTests {
    @Test func `companion page limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.pageLimitExceeded(maxCompanionPageCount)

        #expect(maxCompanionPageCount == 100)
        #expect(error.errorDescription?.contains("100 pages") == true)
        #expect(error.errorDescription?.contains("protect this device") == true)
    }

    @Test func `companion response limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.responsePageTooLarge(maxCompanionPageBytes)

        #expect(maxCompanionPageBytes == 2_097_152)
        #expect(error.errorDescription?.contains("2097152-byte") == true)
        #expect(error.errorDescription?.contains("Loading stopped") == true)
    }

    @Test func `companion item limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)

        #expect(maxCompanionItemCount == 1000)
        #expect(!companionItemLimitExceeded(current: 999, adding: 1))
        #expect(companionItemLimitExceeded(current: 999, adding: 2))
        #expect(error.errorDescription?.contains("1000 items") == true)
        #expect(error.errorDescription?.contains("protect this device") == true)
    }

    @Test func `companion page tokens have a UTF-8 byte ceiling`() {
        #expect(companionPageTokenLengthError(String(repeating: "x", count: 256)) == nil)
        let error = companionPageTokenLengthError(String(repeating: "🦺", count: 65))

        #expect(error == .pageTokenTooLong(256))
        #expect(error?.errorDescription?.contains("256 bytes") == true)
    }

    @Test func `whitespace-only companion page tokens terminate pagination`() {
        #expect(nonBlankCompanionPageToken(nil) == nil)
        #expect(nonBlankCompanionPageToken(" \n\t ") == nil)
        #expect(nonBlankCompanionPageToken(" opaque token ") == " opaque token ")
    }

    @Test func `numeric companion page tokens must be positive`() {
        #expect(companionNumericPageToken(-1) == nil)
        #expect(companionNumericPageToken(0) == nil)
        #expect(companionNumericPageToken(2) == "2")
    }

    @Test func `companion endpoint determines its required collection`() {
        #expect(companionCollectionName(for: "api/pads") == "pads")
        #expect(companionCollectionName(for: "/api/questions") == "questions")
        #expect(companionCollectionName(for: "api/unknown") == nil)
        #expect(CompanionLoadError.missingItemCollection("pads").errorDescription?.contains("pads collection") == true)
    }

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

    @Test func `rejects server URLs with queries`() {
        #expect(TVProvisioningRequest(dictionary: [
            "server": "https://example.com/base?tenant=a",
            "apiKey": "x"
        ]) == nil)
    }

    @Test func `rejects server URLs with fragments`() {
        #expect(TVProvisioningRequest(dictionary: [
            "server": "https://example.com/base#section",
            "apiKey": "x"
        ]) == nil)
    }

    @Test func `rejects blank keys and missing payload fields`() {
        #expect(TVProvisioningRequest(dictionary: ["server": "https://example.com", "apiKey": " "]) == nil)
        #expect(TVProvisioningRequest(dictionary: ["server": "https://example.com"]) == nil)
    }

    @Test func `rejects unsafe credential scalars and oversized keys`() {
        for key in ["line\nbreak", "hidden\u{200B}format", String(repeating: "x", count: 4097)] {
            #expect(TVProvisioningRequest(dictionary: [
                "server": "https://example.com",
                "apiKey": key
            ]) == nil)
        }
    }
}
