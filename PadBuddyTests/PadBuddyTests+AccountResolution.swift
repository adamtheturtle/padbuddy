//
//  PadBuddyTests+AccountResolution.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Account server URL resolution")
struct AccountServerURLTests {
    private func account(baseURL: String?) -> Account {
        Account(name: "A", apiKey: "k", userEmail: "me@acme.com", baseURL: baseURL)
    }

    @Test
    func `a blank Server URL resolves to the hosted default and is not malformed`() {
        for raw in [nil, "", "   \n"] {
            let account = account(baseURL: raw)
            #expect(account.resolvedBaseURL == CoderPadClient.defaultBaseURL)
            #expect(!account.hasMalformedBaseURLOverride)
            #expect(account.baseURLOverride == nil)
        }
    }

    @Test
    func `a valid override resolves to itself`() {
        let account = account(baseURL: " https://coderpad.internal/api ")
        #expect(account.baseURLOverride == URL(string: "https://coderpad.internal/api"))
        #expect(account.resolvedBaseURL == URL(string: "https://coderpad.internal/api"))
        #expect(!account.hasMalformedBaseURLOverride)
    }

    @Test
    func `a non-empty invalid override is flagged instead of falling back (#849)`() {
        // A scheme typo, a missing scheme, and a non-HTTP scheme must all be reported
        // as malformed rather than silently sending the key to the hosted endpoint.
        for raw in ["htps://coderpad.internal", "coderpad.internal", "ftp://coderpad.internal", "https://"] {
            let account = account(baseURL: raw)
            #expect(account.hasMalformedBaseURLOverride, "\(raw) should be malformed")
            #expect(account.baseURLOverride == nil, "\(raw) should not parse")
        }
    }

    @Test
    func `server identity folds cosmetic URL spelling differences (#850)`() {
        let canonical = account(baseURL: "https://coderpad.example").serverIdentity
        for spelling in [
            "https://coderpad.example/",
            "HTTPS://CODERPAD.EXAMPLE",
            "https://coderpad.example:443",
            "https://Coderpad.Example:443/"
        ] {
            #expect(account(baseURL: spelling).serverIdentity == canonical, "\(spelling) should match")
        }
    }

    @Test
    func `server identity keeps genuinely different servers apart`() {
        let base = account(baseURL: "https://coderpad.example").serverIdentity
        #expect(account(baseURL: "https://other.example").serverIdentity != base)
        #expect(account(baseURL: "https://coderpad.example:8443").serverIdentity != base)
        #expect(account(baseURL: "http://coderpad.example").serverIdentity != base)
        #expect(account(baseURL: "https://coderpad.example/api").serverIdentity != base)
    }

    @Test
    func `a non-default port and path survive canonicalization`() {
        let account = account(baseURL: "https://Coderpad.Example:8443/api/")
        #expect(account.serverIdentity == "https://coderpad.example:8443/api")
    }
}

@Suite("Account ownership matching")
struct AccountOwnershipTests {
    @Test
    func `owns matches the exact address, ignoring case`() {
        let account = Account(name: "A", apiKey: "k", userEmail: "Me@Acme.co")
        #expect(account.owns("me@acme.co"))
        #expect(account.owns("ME@ACME.CO"))
    }

    @Test
    func `owns treats plus-addressed mailboxes as distinct (#851)`() {
        let base = Account(name: "A", apiKey: "k", userEmail: "hello@acme.co")
        #expect(!base.owns("hello+cursor@acme.co"))

        let alias = Account(name: "B", apiKey: "k", userEmail: "hello+cursor@acme.co")
        #expect(!alias.owns("hello@acme.co"))
        #expect(!alias.owns("hello+other@acme.co"))
        #expect(alias.owns("hello+cursor@acme.co"))
    }

    @Test
    func `owns rejects a different mailbox or domain`() {
        let account = Account(name: "A", apiKey: "k", userEmail: "hello@acme.co")
        #expect(!account.owns("someone@acme.co"))
        #expect(!account.owns("hello@other.co"))
    }

    @Test
    func `owns never matches when either side is empty`() {
        // A draft account (empty email) must not claim an unowned pad, and a real
        // account must not match a pad whose owner_email is blank.
        let draft = Account(name: "A", apiKey: "k", userEmail: "")
        #expect(!draft.owns(""))
        #expect(!draft.owns("hello@acme.co"))
        let real = Account(name: "B", apiKey: "k", userEmail: "hello@acme.co")
        #expect(!real.owns(""))
    }
}

@Suite("Account-scoped defaults purge (#914)")
struct AccountScopedDefaultsTests {
    @Test
    func `purging removes every key embedding the account UUID and keeps the rest`() throws {
        let suiteName = "PadBuddyTests.purge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UUID()
        defaults.set("owner:candidate@acme.co", forKey: "pads.liveFilter.\(account.uuidString)")
        defaults.set("row-7", forKey: "questions.selectedQuestion.\(account.uuidString)")
        defaults.set("pads", forKey: "section.\(account.uuidString)")
        defaults.set("draft", forKey: "creationDraft.v1.pad.\(account.uuidString)")
        defaults.set("prompt", forKey: "creationDraft.v1.question.\(account.uuidString)")
        defaults.set(12, forKey: "screen.selectedCampaign.v1.\(account.uuidString)")
        defaults.set("\(account.uuidString):12", forKey: "screen.selectedMergedCampaign.v1")
        defaults.set(1.0, forKey: "organization.customRange.account.\(account.uuidString).start")
        defaults.set(2.0, forKey: "organization.customRange.account.\(account.uuidString).end")
        defaults.set(["lang"], forKey: "dismissedFilterSuggestions.v1.pads.\(account.uuidString)")
        defaults.set(["team"], forKey: "dismissedFilterSuggestions.v1.questions.\(account.uuidString)")
        defaults.set("unrelated", forKey: "general.appearance")

        AccountScopedDefaults.purge(account: account, defaults: defaults)

        #expect(defaults.string(forKey: "pads.liveFilter.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "questions.selectedQuestion.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "section.\(account.uuidString)") == nil)
        #expect(defaults.data(forKey: "creationDraft.v1.pad.\(account.uuidString)") == nil)
        #expect(defaults.data(forKey: "creationDraft.v1.question.\(account.uuidString)") == nil)
        #expect(defaults.object(forKey: "screen.selectedCampaign.v1.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "screen.selectedMergedCampaign.v1") == nil)
        #expect(defaults.object(forKey: "organization.customRange.account.\(account.uuidString).start") == nil)
        #expect(defaults.object(forKey: "organization.customRange.account.\(account.uuidString).end") == nil)
        #expect(defaults.object(forKey: "dismissedFilterSuggestions.v1.pads.\(account.uuidString)") == nil)
        #expect(defaults.object(forKey: "dismissedFilterSuggestions.v1.questions.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "general.appearance") == "unrelated")
    }

    @Test
    func `each removed account still gets a legacy defaults sweep`() throws {
        let suiteName = "PadBuddyTests.purge.legacy-per-account.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = UUID()
        let second = UUID()
        defaults.set("a", forKey: "unregistered.\(first.uuidString)")
        defaults.set("b", forKey: "unregistered.\(second.uuidString)")

        AccountScopedDefaults.purge(account: first, defaults: defaults)
        AccountScopedDefaults.purge(account: second, defaults: defaults)

        #expect(defaults.string(forKey: "unregistered.\(first.uuidString)") == nil)
        #expect(defaults.string(forKey: "unregistered.\(second.uuidString)") == nil)
    }

    @Test
    func `later purges of the same account use the registered keys without resweeping`() throws {
        let suiteName = "PadBuddyTests.purge.registry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UUID()
        AccountScopedDefaults.purge(account: account, defaults: defaults)
        defaults.set("saved", forKey: "pads.topRow.\(account.uuidString)")
        defaults.set("future", forKey: "unregistered.\(account.uuidString)")

        AccountScopedDefaults.purge(account: account, defaults: defaults)

        #expect(defaults.string(forKey: "pads.topRow.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "unregistered.\(account.uuidString)") == "future")
    }

    @Test
    func `purging leaves another account merged Screen selection alone`() throws {
        let suiteName = "PadBuddyTests.purge.merged-screen.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let removed = UUID()
        let kept = UUID()
        defaults.set("\(kept.uuidString):9", forKey: "screen.selectedMergedCampaign.v1")

        AccountScopedDefaults.purge(account: removed, defaults: defaults)

        #expect(defaults.string(forKey: "screen.selectedMergedCampaign.v1") == "\(kept.uuidString):9")
    }
}
