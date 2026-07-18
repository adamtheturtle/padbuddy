//
//  coderpadTests+Services.swift
//  coderpadTests
//
//  The "Open Pad in CoderPad" macOS Service's id extraction (#795, #1044,
//  #1246-#1248), split from coderpadTests.swift for the file-length lint.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Open Pad service id extraction")
struct ServicesProviderTests {
    private let hosts: Set<String> = ["app.coderpad.io:443", "pads.acme.example:443"]

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
            fromSelection: "coderpad://pad/XYZ789", allowedEndpoints: hosts
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
            fromSelection: "coderpad://untrusted/ABC123", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "coderpad://pad/foo/bar", allowedEndpoints: hosts
        ) == nil)
        #expect(ServicesProvider.padID(
            fromSelection: "coderpad://pad/a%20b", allowedEndpoints: hosts
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
        #expect(ServicesProvider.padID(fromSelection: "coderpad://pad/", allowedEndpoints: hosts) == nil)
    }
}
