//
//  PadBuddyTests+Services.swift
//  PadBuddyTests
//
//  The "Open Pad in CoderPad" macOS Service's id extraction (#795, #1044,
//  #1246-#1248), split from PadBuddyTests.swift for the file-length lint.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Open Pad service id extraction")
struct ServicesProviderTests {
    private let hosts: Set<String> = ["https://app.coderpad.io:443", "https://pads.acme.example:443"]

    @Test func `oversized selected text is rejected before URL parsing`() {
        let oversized = "https://app.coderpad.io/abc123?payload="
            + String(repeating: "x", count: ServicesProvider.maximumSelectionBytes)
        #expect(ServicesProvider.padID(fromSelection: oversized, allowedEndpoints: hosts) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: String(repeating: " ", count: 1_000_000) + "abc123", allowedEndpoints: hosts
        ) == nil)
    }

    @Test
    func `extracts the id from a CoderPad web URL`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io/ABC123", allowedEndpoints: hosts
        ) == "ABC123")
    }

    @Test
    func `ignores trailing path components like playback`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io/ABC123/playback", allowedEndpoints: hosts
        ) == "ABC123")
    }

    @Test
    func `accepts a configured custom server host (#795)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://pads.acme.example/DEF456", allowedEndpoints: hosts
        ) == "DEF456")
    }

    @Test
    func `rejects web URLs from unknown hosts (#795)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://example.com/invoices", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io.evil.example/ABC123", allowedEndpoints: hosts
        ) == nil)
    }

    @Test
    func `reads the id from a coderpad deep link`() {
        #expect(ServicesProvider.padID(
            fromSelection: "com.adamdangoor.padbuddy://pad/XYZ789", allowedEndpoints: hosts
        ) == "XYZ789")
    }

    @Test
    func `rejects a same-host link on a different port (#1248)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://pads.acme.example:8443/DEF456", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io:443/ABC123", allowedEndpoints: hosts
        ) == "ABC123")
    }

    @Test
    func `rejects coderpad-scheme selections that are not pad deep links (#1246)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "com.adamdangoor.padbuddy://untrusted/ABC123", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "com.adamdangoor.padbuddy://pad/foo/bar", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "com.adamdangoor.padbuddy://pad/a%20b", allowedEndpoints: hosts
        ) == nil)
    }

    @Test
    func `rejects a plain-HTTP link to an HTTPS-only server (#1933)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "http://app.coderpad.io:443/ABC123", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "http://app.coderpad.io/ABC123", allowedEndpoints: hosts
        ) == nil)
    }

    @Test
    func `rejects repeated or unknown pad-page suffixes (#1936)`() {
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io/ABC123/playback/playback", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "https://app.coderpad.io/ABC123/settings", allowedEndpoints: hosts
        ) == nil)
    }

    @Test
    func `accepts a bare alphanumeric id token`() {
        #expect(ServicesProvider.padID(fromSelection: "  ABC123  ", allowedEndpoints: hosts) == "ABC123")
    }

    @Test
    func `rejects arbitrary prose so it doesn't fire a bogus open`() {
        #expect(ServicesProvider.padID(fromSelection: "let's open the pad", allowedEndpoints: hosts) == nil)
        #expect(ServicesProvider.padID(fromSelection: "", allowedEndpoints: hosts) == nil)
        let appURL = "com.adamdangoor.padbuddy://pad/"
        #expect(ServicesProvider.padID(fromSelection: appURL, allowedEndpoints: hosts) == nil)
    }
}
