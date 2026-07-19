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
