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
        #expect(decoded.name == "Demo (mock data)")
    }

    @Test
    func `demo accounts carry the required user email`() {
        #expect(Account.demo().userEmail == Account.demoUserEmail)
        #expect(Account.demoBadKey().userEmail == Account.demoUserEmail)
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
    func `an account persisted without a user email fails to decode`() {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","apiKey":"k","isMock":false,"userEmail":""}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        }
    }

    @Test
    func `a missing-email account is dropped on load without sinking valid siblings`() throws {
        // The store decodes elements leniently, so one invalid account must not take
        // the rest down with it.
        let valid = Account(name: "Good", apiKey: "k", userEmail: "me@acme.com")
        let validJSON = try #require(String(bytes: JSONEncoder().encode(valid), encoding: .utf8))
        let array = """
        [\(validJSON),{"id":"\(UUID().uuidString)","name":"Bad","apiKey":"k","userEmail":""}]
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

@Suite("Account ownership matching")
struct AccountOwnershipTests {
    @Test
    func `owns matches the exact address, ignoring case`() {
        let account = Account(name: "A", apiKey: "k", userEmail: "Me@Acme.co")
        #expect(account.owns("me@acme.co"))
        #expect(account.owns("ME@ACME.CO"))
    }

    @Test
    func `owns folds plus-addressing in either direction`() {
        // A pad owned via a sub-address alias still counts as the base mailbox's owner.
        let base = Account(name: "A", apiKey: "k", userEmail: "hello@acme.co")
        #expect(base.owns("hello+cursor@acme.co"))
        // And an account configured with the alias still owns base-addressed pads.
        let alias = Account(name: "B", apiKey: "k", userEmail: "hello+cursor@acme.co")
        #expect(alias.owns("hello@acme.co"))
        #expect(alias.owns("hello+other@acme.co"))
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
