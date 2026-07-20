//
//  coderpadTests+AccountCredentialIdentity.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Account credential identity")
struct AccountCredentialIdentityTests {
    @Test
    func `canonicalizes key and server aliases`() {
        let first = Account(
            name: "First", apiKey: " key ", userEmail: "first@example.com",
            baseURL: "https://EXAMPLE.com:443/"
        )
        let duplicate = Account(
            name: "Second", apiKey: "key", userEmail: "second@example.com",
            baseURL: "https://example.com"
        )
        let otherServer = Account(
            name: "Other", apiKey: "key", userEmail: "other@example.com",
            baseURL: "https://other.example.com"
        )

        #expect(first.hasSameBackendCredentials(as: duplicate))
        #expect(!first.hasSameBackendCredentials(as: otherServer))
    }
}
