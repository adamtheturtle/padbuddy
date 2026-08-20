@testable import PadBuddy
import Foundation
import Security
import Testing

@Suite("Companion provisioning payloads")
struct TVProvisioningTests {
    @Test func `keychain deletion succeeds when the item is removed or already absent (#4659)`() {
        #expect(companionKeychainDeletionSucceeded(errSecSuccess))
        #expect(companionKeychainDeletionSucceeded(errSecItemNotFound))
        #expect(!companionKeychainDeletionSucceeded(errSecAuthFailed))
        #expect(!companionKeychainDeletionSucceeded(errSecInteractionNotAllowed))
    }

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

    @Test func `companion retained data has an aggregate byte ceiling`() {
        let error = CompanionLoadError.retainedDataLimitExceeded(maxCompanionRetainedBytes)

        #expect(maxCompanionRetainedBytes == 524_288)
        #expect(!companionRetainedByteLimitExceeded(current: 500_000, adding: 24288))
        #expect(companionRetainedByteLimitExceeded(current: 500_000, adding: 24289))
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

    @Test func `companion item decoder accepts string and numeric identities`() throws {
        #expect(try JSONDecoder().decode(CompanionItemID.self, from: Data("\" pad-42 \"".utf8)).value == "pad-42")
        #expect(try JSONDecoder().decode(CompanionItemID.self, from: Data("42".utf8)).value == "42")
    }

    @Test func `companion item decoder preserves malformed type failure`() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompanionItemID.self, from: Data("true".utf8))
        }
    }

    @Test func `companion titles are reduced to a safe display line`() {
        #expect(normalizedCompanionTitle("  First\n\tSecond  ", fallback: "Untitled") == "First Second")
        #expect(normalizedCompanionTitle("safe\u{202E}deceptive", fallback: "Untitled") == "safedeceptive")
        #expect(normalizedCompanionTitle("\u{0000}\u{200E}", fallback: "Untitled") == "Untitled")
    }

    @Test func `companion titles have byte and character ceilings`() {
        let ascii = normalizedCompanionTitle(String(repeating: "x", count: 1000), fallback: "Untitled")
        let emoji = normalizedCompanionTitle(String(repeating: "🦺", count: 1000), fallback: "Untitled")

        #expect(ascii.count == maxCompanionTitleCharacters)
        #expect(emoji.utf8.count <= maxCompanionTitleBytes)
        #expect(emoji.count <= maxCompanionTitleCharacters)
    }

    @Test func `companion cancellation recognizes task and transport cancellation`() {
        #expect(isCompanionCancellation(CancellationError()))
        #expect(isCompanionCancellation(URLError(.cancelled)))
        #expect(!isCompanionCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func `watch connectivity activation failures are actionable`() {
        #expect(watchConnectivityActivationFailure(isActivated: true, errorDescription: nil) == nil)
        #expect(watchConnectivityActivationFailure(isActivated: false, errorDescription: nil)?.isEmpty == false)
        let detailed = watchConnectivityActivationFailure(isActivated: false, errorDescription: "Not paired")
        #expect(detailed?.contains("Not paired") == true)
    }

    @Test func `iPhone watch activation failures are actionable`() {
        #expect(iPhoneWatchActivationFailure(isActivated: true, errorDescription: nil) == nil)
        #expect(iPhoneWatchActivationFailure(isActivated: false, errorDescription: nil)?.isEmpty == false)
        let detailed = iPhoneWatchActivationFailure(isActivated: false, errorDescription: "Not paired")
        #expect(detailed?.contains("Not paired") == true)
    }

    @Test func `companion status belongs only to its initiating account`() {
        let first = UUID()

        #expect(companionStatusBelongsToAccount(statusAccountID: first, accountID: first))
        #expect(!companionStatusBelongsToAccount(statusAccountID: first, accountID: UUID()))
        #expect(!companionStatusBelongsToAccount(statusAccountID: nil, accountID: first))
    }

    @Test func `companion success becomes stale when availability is lost`() {
        #expect(!companionSuccessIsStale(isSuccess: true, isAvailable: true))
        #expect(companionSuccessIsStale(isSuccess: true, isAvailable: false))
        #expect(!companionSuccessIsStale(isSuccess: false, isAvailable: false))
    }

    @Test func `watch provisioning revisions reject delayed payloads`() {
        #expect(shouldApplyWatchProvisioningRevision(nil, latest: nil))
        #expect(!shouldApplyWatchProvisioningRevision(nil, latest: 1))
        #expect(shouldApplyWatchProvisioningRevision(2, latest: 1))
        #expect(!shouldApplyWatchProvisioningRevision(1, latest: 1))
        #expect(!shouldApplyWatchProvisioningRevision(1, latest: 2))
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

    @Test func `only the latest watch provisioning attempt may publish`() {
        var order = CompanionReloadOrder()
        let supersededAttempt = order.begin()
        let currentAttempt = order.begin()

        #expect(!order.isCurrent(supersededAttempt))
        #expect(order.isCurrent(currentAttempt))
    }

    @Test func `accepts an HTTPS nearby-device payload`() throws {
        let request = try #require(TVProvisioningRequest(dictionary: [
            "server": "https://app.coderpad.io",
            "apiKey": "secret"
        ]))
        #expect(request.server == URL(string: "https://app.coderpad.io"))
        #expect(request.apiKey == "secret")
    }

    @Test func `accepts case insensitive HTTPS schemes`() throws {
        let request = try #require(TVProvisioningRequest(dictionary: [
            "server": "HTTPS://app.coderpad.io",
            "apiKey": "secret"
        ]))
        let server = try #require(URL(string: "Https://app.coderpad.io"))

        #expect(request.server.host == "app.coderpad.io")
        #expect(TVProvisioningRequest.payload(server: server, apiKey: "secret") != nil)
    }

    @Test func `rejects insecure servers and credentials in server URLs`() {
        #expect(TVProvisioningRequest(dictionary: ["server": "http://example.com", "apiKey": "x"]) == nil)
        #expect(TVProvisioningRequest(dictionary: ["server": "https://u:p@example.com", "apiKey": "x"]) == nil)
    }

    @Test func `outgoing companion payloads enforce receiver server policy`() throws {
        let secureServer = try #require(URL(string: "https://example.com"))
        let insecureServer = try #require(URL(string: "http://example.com"))
        let queriedServer = try #require(URL(string: "https://example.com?tenant=a"))

        #expect(TVProvisioningRequest.payload(server: secureServer, apiKey: "x") != nil)
        #expect(TVProvisioningRequest.payload(server: insecureServer, apiKey: "x") == nil)
        #expect(TVProvisioningRequest.payload(server: queriedServer, apiKey: "x") == nil)
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
