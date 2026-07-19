//
//  coderpadTests+PadUpdateNotifications.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad update notification links")
struct PadUpdateNotificationLinkTests {
    @Test(arguments: ["abc-123", "a?b", "a#b", "a/b", "a%b", "café"])
    func `pad identifiers round-trip as one deep-link component`(id: String) throws {
        let accountID = UUID()
        let url = try #require(PadUpdateNotifier.notificationURL(padID: id, accountID: accountID))

        #expect(CoderpadApp.padID(fromDeepLink: url) == id)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "account" })?.value == accountID.uuidString)
    }

    @Test
    func `malformed pad deep links are rejected`() throws {
        #expect(PadUpdateNotifier.notificationURL(padID: "", accountID: nil) == nil)
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "coderpad://pad"))) == nil)
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "coderpad://pad/a/b"))) == nil)
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "coderpad://pad/%00"))) == nil)
    }
}
