//
//  coderpadTests+PadHandoff.swift
//  coderpadTests
//
//  Tests for incoming pad Handoff activity URL validation.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad Handoff activity URLs")
@MainActor
struct PadHandoffTests {
    @Test
    func `accepts trusted CoderPad webpage URLs`() throws {
        let url = try #require(URL(string: "https://app.coderpad.io/ABC123"))
        let activity = NSUserActivity(activityType: PadActivity.type)
        activity.webpageURL = url

        #expect(padActivityURL(activity) == url)
    }

    @Test
    func `accepts trusted fallback URL strings`() throws {
        let url = try #require(URL(string: "https://app.coderpad.io/ABC123/playback"))
        let activity = NSUserActivity(activityType: PadActivity.type)
        activity.addUserInfoEntries(from: [PadActivity.urlKey: url.absoluteString])

        #expect(padActivityURL(activity) == url)
    }

    @Test
    func `rejects arbitrary Handoff URLs (#847)`() {
        for raw in [
            "https://example.invalid/phish",
            "https://app.coderpad.io.evil.example/ABC123",
            "file:///tmp/secret",
            "coderpad://pad/ABC123",
            "https://app.coderpad.io"
        ] {
            let activity = NSUserActivity(activityType: PadActivity.type)
            activity.webpageURL = URL(string: raw)

            #expect(padActivityURL(activity) == nil, "\(raw) should be rejected")
        }
    }
}
