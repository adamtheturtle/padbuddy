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

@Suite("Widget handoff request ordering (#2590, #2591)")
struct WidgetHandoffOrderingTests {
    @Test
    func `the ordinal parses out of a request filename`() {
        let name = "pending-new-pad-000000001700000000123-\(UUID().uuidString).json"
        #expect(WidgetSharedStore.requestOrdinal(fileName: name) == 1_700_000_000_123)
    }

    @Test
    func `legacy fixed-name requests sort first`() {
        // Files written before ordering existed carry no ordinal, so they read as 0
        // and drain before anything newer rather than sorting unpredictably.
        #expect(WidgetSharedStore.requestOrdinal(fileName: "pending-new-pad.json") == 0)
        #expect(WidgetSharedStore.requestOrdinal(fileName: "pending-open-pad.json") == 0)
    }

    @Test
    func `zero-padded ordinals sort lexically in numeric order`() {
        // The drain sorts by parsed ordinal, but the padding is what keeps a
        // directory listing in the same order, so a shorter later timestamp can't
        // sort before a longer earlier one.
        let earlier = String(format: "%018llu", UInt64(999))
        let later = String(format: "%018llu", UInt64(1_700_000_000_123))
        #expect(earlier < later)
        #expect(earlier.count == later.count)
    }
}
