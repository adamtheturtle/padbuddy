//
//  coderpadTests+PadHistoryValidation.swift
//  coderpadTests
//
//  Tests for the pad-history URL SSRF guard (#856): only HTTPS URLs on trusted
//  CoderPad/Firebase origins (or the account's own API host) may be fetched.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad history URL validation")
struct PadHistoryValidationTests {
    private let hostedBase = URL(string: "https://app.coderpad.io")!

    private func allowed(_ url: String, base: URL? = nil) -> Bool {
        PadHistoryURLValidation.isAllowed(url, accountBaseURL: base ?? hostedBase)
    }

    @Test
    func `trusted CoderPad and Firebase origins are allowed`() {
        #expect(allowed("https://coderpad-1.firebaseio.com/abc/history.json"))
        #expect(allowed("https://coderpad-prod.europe-west1.firebasedatabase.app/abc/history.json"))
        #expect(allowed("https://app.coderpad.io/history/abc"))
    }

    @Test
    func `the account's own API host is allowed for self-hosted deployments`() throws {
        let selfHosted = try #require(URL(string: "https://coderpad.acme.internal"))
        #expect(allowed("https://coderpad.acme.internal/history/abc", base: selfHosted))
        // Other hosts are still rejected for that account.
        #expect(!allowed("https://other.acme.internal/history/abc", base: selfHosted))
    }

    @Test
    func `plain HTTP is rejected even on a trusted origin`() {
        #expect(!allowed("http://coderpad-1.firebaseio.com/abc/history.json"))
        #expect(!allowed("http://app.coderpad.io/history/abc"))
    }

    @Test
    func `localhost, IP literals, and metadata endpoints are rejected`() {
        #expect(!allowed("https://localhost/abc"))
        #expect(!allowed("https://127.0.0.1:8080/abc"))
        #expect(!allowed("https://169.254.169.254/latest/meta-data/"))
        #expect(!allowed("https://[::1]/abc"))
        #expect(!allowed("https://2130706433/abc"))
        #expect(!allowed("https://printer.local/abc"))
    }

    @Test
    func `lookalike and unrelated hosts are rejected`() {
        #expect(!allowed("https://evil.example/abc"))
        #expect(!allowed("https://notfirebaseio.com/abc"))
        #expect(!allowed("https://firebaseio.com.evil.example/abc"))
        #expect(!allowed("ftp://coderpad-1.firebaseio.com/abc"))
        #expect(!allowed(""))
        #expect(!allowed("not a url"))
    }

    @Test
    func `only named production projects are allowed, case-insensitively`() {
        #expect(allowed("HTTPS://CODERPAD-1.FIREBASEIO.COM/abc"))
        #expect(allowed("https://eu.app.coderpad.io/history"))
        #expect(!allowed("https://unrelated-project.firebaseio.com/abc"))
        #expect(!allowed("https://attacker.europe-west1.firebasedatabase.app/abc"))
        #expect(!allowed("https://unrelated.coderpad.io/history"))
    }
}
