//
//  coderpadTests+Keychain.swift
//  coderpadTests
//
//  Guardrail for the buddy-kit extraction (#512): the Keychain service name is a hard
//  compatibility contract. The implementation now lives in BuddyAppKit's KeychainStore
//  with the service injected, but the app must keep pinning "com.coderpad.app"
//  byte-for-byte — change it and every existing user loses their saved accounts, which
//  are keyed by it. This test fails loudly if that string ever drifts.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Keychain service compatibility")
struct KeychainServiceTests {
    @Test
    func `the Keychain service stays com_coderpad_app byte-for-byte`() {
        #expect(Keychain.service == "com.coderpad.app")
    }

    @Test
    func `the account-name keys are unchanged`() {
        #expect(Keychain.accountsAccount == "accounts")
        #expect(Keychain.legacySingleKeyAccount == "apiKey")
    }
}

@Suite("Keychain reconciliation ordering")
struct KeychainReconciliationOrderingTests {
    @Test
    func `equal revisions choose the same bytes on both device orientations`() {
        let lower = Data("account-a".utf8)
        let higher = Data("account-b".utf8)

        #expect(Keychain.shouldAdoptCloud(local: lower, cloud: higher,
                                          localRevision: 10, cloudRevision: 10))
        #expect(!Keychain.shouldAdoptCloud(local: higher, cloud: lower,
                                           localRevision: 10, cloudRevision: 10))
    }

    @Test
    func `revision ordering remains authoritative`() {
        let local = Data("z".utf8)
        let cloud = Data("a".utf8)

        #expect(Keychain.shouldAdoptCloud(local: local, cloud: cloud,
                                          localRevision: 10, cloudRevision: 11))
        #expect(!Keychain.shouldAdoptCloud(local: local, cloud: cloud,
                                           localRevision: 11, cloudRevision: 10))
    }

    @Test
    func `only positive finite cloud revisions are preserved`() {
        #expect(Keychain.normalizedRevisionData(Data("123.5".utf8)) == Data("123.5".utf8))
        for invalid in [nil, Data("bad".utf8), Data("0".utf8), Data("-1".utf8), Data("nan".utf8)] {
            #expect(Keychain.normalizedRevisionData(invalid) == nil)
        }
    }
}

@Suite("Synced account validation")
@MainActor
struct SyncedAccountValidationTests {
    @Test
    func `valid and genuinely empty account lists are usable`() throws {
        let valid = Account(name: "Acme", apiKey: "key", userEmail: "")

        #expect(try Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([valid])))
        #expect(Keychain.decodesToUsableAccounts(Data("[]".utf8)))
    }

    @Test
    func `empty keys and malformed endpoints are rejected`() throws {
        let emptyKey = Account(name: "Acme", apiKey: "   ")
        let badEndpoint = Account(name: "Acme", apiKey: "key", baseURL: "not a URL")

        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([emptyKey])))
        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([badEndpoint])))
    }

    @Test
    func `duplicate IDs and partially malformed lists are rejected`() throws {
        let id = UUID()
        let duplicates = [Account(name: "A", apiKey: "a", id: id), Account(name: "B", apiKey: "b", id: id)]
        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode(duplicates)))

        let validJSON = try #require(String(data: Keychain.accountEncoder.encode([duplicates[0]]), encoding: .utf8))
        let partial = "[\(validJSON.dropFirst().dropLast()),{\"name\":\"missing required fields\"}]"
        #expect(!Keychain.decodesToUsableAccounts(Data(partial.utf8)))
    }
}
