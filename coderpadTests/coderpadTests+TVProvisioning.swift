@testable import CoderPad
import Foundation
import Testing

@Suite("Companion provisioning payloads")
struct TVProvisioningTests {
    @Test func `watch save failures use a stable reply code`() {
        #expect(WatchProvisioningReplyError.saveFailed.rawValue == "save_failed")
    }

    @Test func `malformed watch payloads use a stable reply code`() {
        #expect(WatchProvisioningReplyError.invalidPayload.rawValue == "invalid_payload")
    }

    @Test func `companion page limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.pageLimitExceeded(maxCompanionPageCount)

        #expect(maxCompanionPageCount == 100)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func `companion response limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.responsePageTooLarge(maxCompanionPageBytes)

        #expect(maxCompanionPageBytes == 2_097_152)
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func `companion item limit has actionable bounded failure copy`() {
        let error = CompanionLoadError.itemLimitExceeded(maxCompanionItemCount)

        #expect(maxCompanionItemCount == 1000)
        #expect(!companionItemLimitExceeded(current: 999, adding: 1))
        #expect(companionItemLimitExceeded(current: 999, adding: 2))
        #expect(error.errorDescription?.isEmpty == false)
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

    @Test func `numeric companion item identities must be positive`() {
        #expect(companionNumericItemID(-1) == nil)
        #expect(companionNumericItemID(0) == nil)
        #expect(companionNumericItemID(42) == "42")
    }

    @Test func `string companion item identities trim and reject blanks`() {
        #expect(normalizedCompanionStringID(" pad-42 \n") == "pad-42")
        #expect(normalizedCompanionStringID(" \t ") == nil)
    }

    @Test func `string companion item identities have a byte ceiling`() {
        #expect(normalizedCompanionStringID(String(repeating: "x", count: maxCompanionItemIDBytes)) != nil)
        #expect(normalizedCompanionStringID(String(repeating: "🦺", count: 65)) == nil)
    }

    @Test func `companion titles are reduced to a safe display line`() {
        #expect(normalizedCompanionTitle("  First\n\tSecond  ", fallback: "Untitled") == "First Second")
        #expect(normalizedCompanionTitle("safe\u{202E}deceptive", fallback: "Untitled") == "safedeceptive")
        #expect(normalizedCompanionTitle("\u{0000}\u{200E}", fallback: "Untitled") == "Untitled")
    }

    @Test func `companion titles have byte and character ceilings`() {
        let ascii = normalizedCompanionTitle(String(repeating: "x", count: 1_000), fallback: "Untitled")
        let emoji = normalizedCompanionTitle(String(repeating: "🦺", count: 1_000), fallback: "Untitled")

        #expect(ascii.count == maxCompanionTitleCharacters)
        #expect(emoji.utf8.count <= maxCompanionTitleBytes)
        #expect(emoji.count <= maxCompanionTitleCharacters)
    }

    @Test func `companion cancellation recognizes task and transport cancellation`() {
        #expect(isCompanionCancellation(CancellationError()))
        #expect(isCompanionCancellation(URLError(.cancelled)))
        #expect(!isCompanionCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func `companion search ignores surrounding and whitespace-only input`() {
        #expect(normalizedCompanionSearchQuery(" \n ").isEmpty)
        #expect(normalizedCompanionSearchQuery("  Swift \n") == "Swift")
    }

    @Test func `companion HTTP statuses retain actionable meaning`() {
        #expect(companionHTTPStatusError(204) == nil)
        #expect(companionHTTPStatusError(401) == .unauthorized)
        #expect(companionHTTPStatusError(403) == .forbidden)
        #expect(companionHTTPStatusError(429) == .rateLimited)
        #expect(companionHTTPStatusError(503) == .serverFailure(503))
        #expect(companionHTTPStatusError(418) == .httpFailure(418))
    }

    @Test func `companion language keys fold case variants`() {
        #expect(companionLanguageKey("python") == companionLanguageKey("Python"))
        #expect(companionLanguageKey("PYTHON") == companionLanguageKey("Python"))
    }

    @Test func `companion languages trim labels and reject blanks`() {
        #expect(normalizedCompanionLanguage("  Swift \n") == "Swift")
        #expect(normalizedCompanionLanguage(" \t ") == nil)
        #expect(normalizedCompanionLanguage(nil) == nil)
    }

    @Test func `companion languages have a byte ceiling`() {
        #expect(normalizedCompanionLanguage(String(repeating: "x", count: maxCompanionLanguageBytes)) != nil)
        #expect(normalizedCompanionLanguage(String(repeating: "🦺", count: 17)) == nil)
    }

    @Test func `companion endpoint determines its required collection`() {
        #expect(companionCollectionName(for: "api/pads") == "pads")
        #expect(companionCollectionName(for: "/api/questions") == "questions")
        #expect(companionCollectionName(for: "api/unknown") == nil)
        #expect(CompanionLoadError.missingItemCollection("pads").errorDescription?.contains("pads collection") == true)
    }

    @Test func `companion identity scans reject duplicates`() {
        #expect(!hasDuplicateCompanionIDs(["one", "two"]))
        #expect(hasDuplicateCompanionIDs(["one", "two", "one"]))
        #expect(CompanionLoadError.duplicateItemIdentity.errorDescription?.contains("same item") == true)
    }

    @Test func `companion loading remains active until every reload finishes`() {
        var activity = CompanionReloadActivity()
        activity.begin()
        activity.begin()
        activity.end()
        #expect(activity.isLoading)
        #expect(activity.activeReloads == 1)
        activity.end()
        #expect(!activity.isLoading)
        activity.end()
        #expect(activity.activeReloads == 0)
    }

    @Test func `only the latest companion reload may publish`() {
        var order = CompanionReloadOrder()
        let first = order.begin()
        let second = order.begin()

        #expect(!order.isCurrent(first))
        #expect(order.isCurrent(second))
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
