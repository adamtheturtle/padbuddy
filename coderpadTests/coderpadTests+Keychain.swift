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
}
