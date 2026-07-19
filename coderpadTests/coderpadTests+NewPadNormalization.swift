//
//  coderpadTests+NewPadNormalization.swift
//  coderpadTests
//
//  Split from coderpadTests+Models.swift to keep both files under the
//  file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("New pad request normalization")
struct NewPadRequestNormalizationTests {
    @Test
    func `create body trims optional title and owner fields`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: "  Onsite: Jane  \n",
            language: "python3",
            ownerEmail: "\towner@example.com  ",
            contents: nil,
            notes: nil,
            isPrivate: true,
            executionEnabled: false,
            questionID: 42,
            teamID: "team-1"
        ))

        #expect(body.title == "Onsite: Jane")
        #expect(body.ownerEmail == "owner@example.com")
        #expect(body.language == "python3")
        #expect(body.isPrivate == true)
        #expect(body.executionEnabled == false)
        #expect(body.questionID == 42)
        #expect(body.teamID == "team-1")
    }

    @Test
    func `create body omits whitespace only title and owner fields`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: " \n ",
            language: "python3",
            ownerEmail: "\t",
            contents: nil,
            notes: nil,
            isPrivate: false,
            executionEnabled: true,
            questionID: nil,
            teamID: nil
        ))

        #expect(body.title == nil)
        #expect(body.ownerEmail == nil)
    }

    @Test
    func `create body folds interior control characters in title and owner`() {
        let body = NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
            title: "Onsite:\nJane\tDoe",
            language: "python3",
            ownerEmail: "owner@\u{0}example.com",
            contents: nil,
            notes: nil,
            isPrivate: nil,
            executionEnabled: nil,
            questionID: nil,
            teamID: nil
        ))

        // Folded to a space rather than deleted, so the words either side of the
        // break stay apart instead of running together (#2639).
        #expect(body.title == "Onsite: Jane Doe")
        #expect(body.ownerEmail == "owner@ example.com")
    }

    @Test
    func `create body drops a language the pad API cannot create`() {
        func language(_ value: String?) -> String? {
            NewPadSheet.normalizedCreateBody(NewPadSheet.CreateDraft(
                title: nil,
                language: value,
                ownerEmail: nil,
                contents: nil,
                notes: nil,
                isPrivate: nil,
                executionEnabled: nil,
                questionID: nil,
                teamID: nil
            )).language
        }

        // Project environments and unknown codes are rejected by the create API, so
        // they're dropped and the account default applies instead (#2638).
        #expect(language("react") == nil)
        #expect(language("not-a-language") == nil)
        #expect(language("  ") == nil)
        #expect(language(nil) == nil)
        // A supported code survives, canonicalized to the form the gate matched.
        #expect(language("python3") == "python3")
        #expect(language("  Python3 ") == "python3")
    }
}

@Suite("Quota pace projection (#2391)")
struct QuotaPaceProjectionTests {
    private func quota(used: Int, limit: Int) throws -> Quota {
        // Reset one day from "now"; the cycle start is a month before that, so the
        // fraction elapsed is close to 1 and the projection stays near `used`.
        let reset = Date().addingTimeInterval(24 * 60 * 60)
        let iso = ISO8601DateFormatter().string(from: reset)
        let data = try JSONSerialization.data(withJSONObject: [
            "pads_used": used, "billing_cycle_pad_limit": limit, "quota_reset_at": iso
        ])
        return try CoderPadClient.decoder.decode(Quota.self, from: data)
    }

    @Test
    func `a large plan's projection is not clamped below its limit`() throws {
        // The old 9,999 ceiling made a 20,000-pad plan heading well past its limit
        // compare as under it, so the card said "on track" (#2391).
        let pace = try #require(QuotaPace(quota: quota(used: 25000, limit: 20000), now: Date()))
        #expect(pace.projectedUsage >= 25000)
        #expect(pace.status == .over)
    }

    @Test
    func `a projection never falls below what has already been used`() throws {
        let pace = try #require(QuotaPace(quota: quota(used: 12000, limit: 50000), now: Date()))
        #expect(pace.projectedUsage >= 12000)
    }

    @Test
    func `an unlimited or limitless plan has no pace`() throws {
        let unlimited = try JSONSerialization.data(withJSONObject: ["unlimited": true])
        let decoded = try CoderPadClient.decoder.decode(Quota.self, from: unlimited)
        #expect(QuotaPace(quota: decoded, now: Date()) == nil)
    }
}

@Suite("Organization SSO portal URL (#2378)")
struct OrganizationPortalURLTests {
    @Test
    func `only https web addresses are accepted`() {
        #expect(OrganizationView.portalURL("https://sso.example.com/login") != nil)
        #expect(OrganizationView.portalURL("  https://sso.example.com/login  ") != nil)
    }

    @Test
    func `other schemes are refused`() {
        // The result is handed straight to the system browser, so a file or custom
        // scheme from the organization response must not reach it (#2378).
        #expect(OrganizationView.portalURL("file:///etc/passwd") == nil)
        #expect(OrganizationView.portalURL("http://sso.example.com") == nil)
        #expect(OrganizationView.portalURL("javascript:alert(1)") == nil)
        #expect(OrganizationView.portalURL("someapp://open") == nil)
    }

    @Test
    func `malformed or hostless values are refused`() {
        #expect(OrganizationView.portalURL("") == nil)
        #expect(OrganizationView.portalURL("https://") == nil)
        #expect(OrganizationView.portalURL("not a url") == nil)
    }
}

@Suite("Favorite question shortcut identity (#2359)")
struct FavoriteQuestionEntityIDTests {
    @Test
    func `the key fingerprint is dropped from a sync identifier`() {
        // syncID is endpoint|email|fingerprint, so the entity id is
        // sync|endpoint|email|fingerprint|question. Rotating the key changes only
        // the fingerprint, and configured Shortcuts must survive that (#2359).
        let before = "sync|https://app.coderpad.io|me@example.com|abc123|42"
        let after = "sync|https://app.coderpad.io|me@example.com|def456|42"
        #expect(FavoriteQuestionQuery.keyIndependentID(before)
            == FavoriteQuestionQuery.keyIndependentID(after))
    }

    @Test
    func `a different question or account still differs`() {
        let base = "sync|https://app.coderpad.io|me@example.com|abc123|42"
        let otherQuestion = "sync|https://app.coderpad.io|me@example.com|abc123|43"
        let otherAccount = "sync|https://app.coderpad.io|other@example.com|abc123|42"
        #expect(FavoriteQuestionQuery.keyIndependentID(base)
            != FavoriteQuestionQuery.keyIndependentID(otherQuestion))
        #expect(FavoriteQuestionQuery.keyIndependentID(base)
            != FavoriteQuestionQuery.keyIndependentID(otherAccount))
    }

    @Test
    func `a legacy or unrecognized identifier passes through unchanged`() {
        let legacy = "\(UUID().uuidString):42"
        #expect(FavoriteQuestionQuery.keyIndependentID(legacy) == legacy)
        #expect(FavoriteQuestionQuery.keyIndependentID("").isEmpty)
    }
}

@Suite("Widget handoff parameter validation (#2364)")
struct WidgetHandoffValidationTests {
    @Test
    func `an absent or blank account means the current one`() {
        #expect(WidgetSharedStore.validatedAccount(nil) == .some(nil))
        #expect(WidgetSharedStore.validatedAccount("") == .some(nil))
        #expect(WidgetSharedStore.validatedAccount("   ") == .some(nil))
    }

    @Test
    func `a well-formed account is normalized to canonical form`() {
        let id = UUID()
        #expect(WidgetSharedStore.validatedAccount(id.uuidString.lowercased())
            == .some(id.uuidString))
        #expect(WidgetSharedStore.validatedAccount("  \(id.uuidString)  ") == .some(id.uuidString))
    }

    @Test
    func `a string that is not an account identifier is refused`() {
        // nil (rather than .some(nil)) is the caller's signal to refuse the request
        // outright, instead of queueing one nothing can route (#2364).
        #expect(WidgetSharedStore.validatedAccount("not-a-uuid") == nil)
        #expect(WidgetSharedStore.validatedAccount("../../etc/passwd") == nil)
    }
}

@Suite("Search Pads intent query bounds (#2354)")
struct SearchPadsQueryTests {
    /// Mirrors the normalization `SearchPadsIntent.perform()` applies before the query
    /// becomes durable navigation state.
    private func normalized(_ query: String) -> String {
        String(query.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(SearchPadsIntent.maxQueryLength))
    }

    @Test
    func `a whitespace-only query becomes an empty search`() {
        #expect(normalized("   \n\t ").isEmpty)
    }

    @Test
    func `surrounding whitespace is trimmed`() {
        #expect(normalized("  swift  ") == "swift")
    }

    @Test
    func `an oversized query is truncated`() {
        let long = String(repeating: "a", count: SearchPadsIntent.maxQueryLength * 3)
        #expect(normalized(long).count == SearchPadsIntent.maxQueryLength)
    }
}

@Suite("Bulk delete batch outcome (#2342, #2346)")
struct BulkDeleteRunnerTests {
    @MainActor
    @Test
    func `every item is attempted and reported`() async {
        var seen: [Int] = []
        let outcome = await BulkDeleteRunner.run(
            Array(1 ... 10),
            title: { "item \($0)" },
            onProgress: { _ in },
            delete: { item in
                seen.append(item)
                return nil
            }
        )
        #expect(seen.sorted() == Array(1 ... 10))
        #expect(outcome.deleted == 10)
        #expect(outcome.failedTitles.isEmpty)
        #expect(!outcome.aborted)
    }

    @MainActor
    @Test
    func `progress reaches the total`() async {
        var last: BulkDeleteProgress?
        _ = await BulkDeleteRunner.run(
            Array(1 ... 7),
            title: { "\($0)" },
            onProgress: { last = $0 },
            delete: { _ in nil }
        )
        #expect(last == BulkDeleteProgress(completed: 7, total: 7))
    }

    @MainActor
    @Test
    func `an ordinary failure does not stop the rest`() async {
        var attempted = 0
        let outcome = await BulkDeleteRunner.run(
            Array(1 ... 8),
            title: { "\($0)" },
            onProgress: { _ in },
            delete: { item in
                attempted += 1
                return item == 1 ? URLError(.badServerResponse) : nil
            }
        )
        #expect(attempted == 8)
        #expect(outcome.failedTitles == ["1"])
        #expect(!outcome.aborted)
    }

    @MainActor
    @Test
    func `a systemic failure stops the batch early`() async {
        // Being offline means every remaining delete would fail the same way, so the
        // queue is abandoned rather than issuing dozens of doomed requests (#2346).
        var attempted = 0
        let outcome = await BulkDeleteRunner.run(
            Array(1 ... 40),
            title: { "\($0)" },
            onProgress: { _ in },
            delete: { _ in
                attempted += 1
                return URLError(.notConnectedToInternet)
            }
        )
        #expect(outcome.aborted)
        #expect(attempted <= BulkDeleteUndo.concurrency)
        #expect(BulkDeleteUndo.report(outcome, total: 40, kind: .pads) != nil)
    }

    @Test
    func `only failures that would repeat count as systemic`() {
        #expect(BulkDeleteUndo.isSystemic(URLError(.notConnectedToInternet)))
        #expect(!BulkDeleteUndo.isSystemic(URLError(.badServerResponse)))
    }
}
