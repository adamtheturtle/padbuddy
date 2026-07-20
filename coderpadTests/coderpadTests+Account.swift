//
//  coderpadTests+Account.swift
//  coderpadTests
//
//  Account model tests: Codable round-trip (including optional Screen credentials),
//  back-compatible legacy decoding, and owner-email matching.
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

@Suite("Account round-trip")
struct AccountRoundTripTests {
    @Test
    func `account encodes/decodes through JSON without loss`() throws {
        let original = Account(name: "Production", apiKey: "secret-key", isMock: false, userEmail: "me@acme.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.apiKey == original.apiKey)
        #expect(decoded.isMock == original.isMock)
    }

    @Test
    func `demo account survives the round-trip with isMock = true`() throws {
        let demo = Account.demo()
        let data = try JSONEncoder().encode(demo)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.isMock == true)
        #expect(decoded.name == MockFixtures.orgName)
    }

    @Test
    func `demo accounts carry the required user email`() {
        #expect(Account.demo().userEmail == Account.demoUserEmail)
        #expect(Account.demoBadKey().userEmail == Account.demoUserEmail)
    }

    @Test
    func `only usable non-demo accounts are eligible for remote Interview fan-outs`() {
        let usable = Account(name: "Production", apiKey: "key", userEmail: "owner@example.com")
        let blank = Account(name: "Blank", apiKey: "  ", userEmail: "owner@example.com")
        let malformed = Account(
            name: "Malformed", apiKey: "key", userEmail: "owner@example.com", baseURL: "not a URL"
        )

        #expect(usable.isRemoteInterviewFetchEligible)
        #expect(!blank.isRemoteInterviewFetchEligible)
        #expect(!malformed.isRemoteInterviewFetchEligible)
        #expect(!Account.demo().isRemoteInterviewFetchEligible)
        #expect(!Account.demoBadKey().isRemoteInterviewFetchEligible)
    }

    @Test
    func `normalizing for storage trims the Interview API key (#771)`() {
        let account = Account(name: "Acme", apiKey: "  live-key\n", userEmail: "me@acme.com")

        #expect(account.normalizedForStorage.apiKey == "live-key")
    }

    @Test
    func `makeClient trims a stored Interview API key defensively (#771)`() {
        let account = Account(name: "Acme", apiKey: "  live-key\n", userEmail: "me@acme.com")

        #expect(account.makeClient().apiKey == "live-key")
    }

    @Test
    func `makeClient memoizes one client per set of credentials (#2111)`() {
        ClientMemo.removeAll()
        var account = Account(name: "Acme", apiKey: "live-key", userEmail: "me@acme.com")

        _ = account.makeClient()
        _ = account.makeClient()
        #expect(ClientMemo.count == 1)

        // A re-keyed account misses the memo rather than being handed a client for
        // credentials it no longer has.
        account.apiKey = "rotated-key"
        #expect(account.makeClient().apiKey == "rotated-key")
        #expect(ClientMemo.count == 2)

        // The two demos share a server but must stay distinct clients.
        ClientMemo.removeAll()
        #expect(Account.demo().makeClient().apiKey != Account.demoBadKey().makeClient().apiKey)
        #expect(ClientMemo.count == 2)
    }

    @Test
    func `icon symbol and tint survive the round-trip`() throws {
        let original = Account(
            name: "Acme", apiKey: "k", userEmail: "me@acme.com",
            iconSymbol: "star.fill", tintHex: "#FF8800"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.iconSymbol == "star.fill")
        #expect(decoded.tintHex == "#FF8800")
    }

    @Test
    func `account saved before icon/tint existed still decodes`() throws {
        // JSON from an older build with no iconSymbol/tintHex keys must not fail to load.
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","apiKey":"k","isMock":false,"userEmail":"me@acme.com"}
        """
        let decoded = try JSONDecoder().decode(Account.self, from: Data(legacy.utf8))
        #expect(decoded.iconSymbol == nil)
        #expect(decoded.tintHex == nil)
    }

    @Test
    func `screen key and region survive the round-trip`() throws {
        let original = Account(
            name: "Acme", apiKey: "k", userEmail: "me@acme.com",
            screenApiKey: "screen-secret", screenRegion: .europe
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        #expect(decoded.screenApiKey == "screen-secret")
        #expect(decoded.screenRegion == .europe)
    }

    @Test
    func `account saved before screen support still decodes with defaults`() throws {
        // JSON from a build with no screenApiKey/screenRegion keys must not fail to
        // load, and must default to no Screen access in the US region.
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","apiKey":"k","isMock":false,"userEmail":"me@acme.com"}
        """
        let decoded = try JSONDecoder().decode(Account.self, from: Data(legacy.utf8))
        #expect(decoded.screenApiKey == nil)
        #expect(decoded.screenRegion == .unitedStates)
    }

    @Test
    func `makeScreenClient returns nil without a key`() {
        let noKey = Account(name: "A", apiKey: "k", userEmail: "me@acme.com")
        #expect(noKey.makeScreenClient() == nil)
        // A whitespace-only key counts as absent.
        let blank = Account(name: "B", apiKey: "k", userEmail: "me@acme.com", screenApiKey: "   ")
        #expect(blank.makeScreenClient() == nil)
    }

    @Test
    func `hasScreenAccess agrees with makeScreenClient`() {
        // Views filter Screen-enabled accounts with the cheap `hasScreenAccess` check
        // instead of building a client each time (#2117), so the two must never
        // disagree about which accounts belong in the Screen lists.
        let accounts = [
            Account(name: "None", apiKey: "k", userEmail: "me@acme.com"),
            Account(name: "Blank", apiKey: "k", userEmail: "me@acme.com", screenApiKey: "   "),
            Account(name: "Keyed", apiKey: "k", userEmail: "me@acme.com", screenApiKey: "s"),
            Account(name: "Padded", apiKey: "k", userEmail: "me@acme.com", screenApiKey: " s "),
            Account.demo(),
            Account.demoBadKey()
        ]
        for account in accounts {
            #expect(account.hasScreenAccess == (account.makeScreenClient() != nil), "\(account.name)")
        }
    }

    @Test
    func `demo accounts use the in-process mock Screen client`() throws {
        // The demo account has no Screen key, but gets the mock client so the demo can
        // exercise the full Screen UI with fixture data.
        let demoClient = try #require(Account.demo().makeScreenClient())
        #expect(demoClient.baseURL == MockScreen.baseURL)
        // The bad-key demo still gets a (401-answering) mock client, not nil.
        #expect(Account.demoBadKey().makeScreenClient() != nil)
    }

    @Test
    func `makeScreenClient points at the region's server`() throws {
        let usAccount = Account(
            name: "US", apiKey: "k", userEmail: "me@acme.com",
            screenApiKey: "s", screenRegion: .unitedStates
        )
        let usClient = try #require(usAccount.makeScreenClient())
        #expect(usClient.apiKey == "s")
        #expect(usClient.baseURL == ScreenClient.defaultBaseURL)

        let euAccount = Account(
            name: "EU", apiKey: "k", userEmail: "me@acme.com",
            screenApiKey: "s", screenRegion: .europe
        )
        let euClient = try #require(euAccount.makeScreenClient())
        #expect(euClient.baseURL == ScreenClient.euBaseURL)
    }

    @Test
    func `an account persisted without a user email still decodes (#767)`() throws {
        // The legacy single-key migration persists an account with no email after
        // deleting the original credential; dropping it on the next launch would
        // lose the API key with no recovery path.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Default","apiKey":"k","isMock":false,"userEmail":""}
        """
        let decoded = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(decoded.apiKey == "k")
        #expect(decoded.userEmail.isEmpty)
    }

    @Test
    func `a migrated legacy account survives the store round-trip (#767)`() throws {
        // The exact shape migrateLegacyAccounts() persists: no userEmail key at all.
        let migrated = Account(name: "Default", apiKey: "legacy-key")
        let data = try JSONEncoder().encode([migrated])
        let reloaded = try JSONDecoder().decode([LenientElement<Account>].self, from: data)
            .compactMap(\.value)
        #expect(reloaded.map(\.apiKey) == ["legacy-key"])
        // An empty email must never claim ownership of anything.
        #expect(reloaded.allSatisfy { !$0.owns("someone@acme.co") })
    }

    @Test
    func `a corrupt account is dropped on load without sinking valid siblings`() throws {
        // The store decodes elements leniently, so one invalid account must not take
        // the rest down with it.
        let valid = Account(name: "Good", apiKey: "k", userEmail: "me@acme.com")
        let validJSON = try #require(String(bytes: JSONEncoder().encode(valid), encoding: .utf8))
        let array = """
        [\(validJSON),{"id":"not-a-uuid","name":"Bad","apiKey":"k","userEmail":""}]
        """
        let decoded = try JSONDecoder().decode([LenientElement<Account>].self, from: Data(array.utf8))
            .compactMap(\.value)
        #expect(decoded.map(\.name) == ["Good"])
    }

    @Test
    func `icon symbol choices are non-empty and unique`() {
        #expect(!Account.iconSymbolChoices.isEmpty)
        #expect(Set(Account.iconSymbolChoices).count == Account.iconSymbolChoices.count)
    }

    @Test
    func `tint choices are unique and parse as colors`() {
        #expect(!Account.tintChoices.isEmpty)
        #expect(Set(Account.tintChoices).count == Account.tintChoices.count)
        for hex in Account.tintChoices {
            #expect(Color(hex: hex) != nil)
        }
    }

    @Test
    func `avatarTint prefers the custom color over the default`() {
        let custom = Account(name: "A", apiKey: "k", tintHex: "#112233")
        #expect(custom.tintColor != nil)
        // An unset tint falls back to the default (no custom color resolved).
        let plain = Account(name: "B", apiKey: "k")
        #expect(plain.tintColor == nil)
    }
}

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
        let suiteName = "coderpadTests.purge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UUID()
        defaults.set("owner:candidate@acme.co", forKey: "pads.liveFilter.\(account.uuidString)")
        defaults.set("row-7", forKey: "questions.selectedQuestion.\(account.uuidString)")
        defaults.set("pads", forKey: "section.\(account.uuidString)")
        defaults.set("unrelated", forKey: "general.appearance")

        AccountScopedDefaults.purge(account: account, defaults: defaults)

        #expect(defaults.string(forKey: "pads.liveFilter.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "questions.selectedQuestion.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "section.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "general.appearance") == "unrelated")
    }

    @Test
    func `later purges use the registered keys without sweeping unrelated defaults`() throws {
        let suiteName = "coderpadTests.purge.registry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AccountScopedDefaults.purge(account: UUID(), defaults: defaults)
        let account = UUID()
        defaults.set("saved", forKey: "pads.topRow.\(account.uuidString)")
        defaults.set("future", forKey: "unregistered.\(account.uuidString)")

        AccountScopedDefaults.purge(account: account, defaults: defaults)

        #expect(defaults.string(forKey: "pads.topRow.\(account.uuidString)") == nil)
        #expect(defaults.string(forKey: "unregistered.\(account.uuidString)") == "future")
    }
}
