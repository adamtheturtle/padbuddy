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

@Suite("Widget handoff request classification (#2138)")
struct WidgetHandoffRequestKindTests {
    @Test
    func `each request kind is recognized from its filename`() {
        // One directory listing now serves both kinds, so the kind comes from the
        // filename rather than from which listing found it (#2138).
        #expect(WidgetSharedStore.isNewPadRequest(fileName: "pending-new-pad.json") == true)
        #expect(WidgetSharedStore.isNewPadRequest(fileName: "pending-open-pad.json") == false)
        let ordinal = String(format: "%018llu", UInt64(1_700_000_000_123))
        #expect(WidgetSharedStore
            .isNewPadRequest(fileName: "pending-new-pad-\(ordinal)-\(UUID().uuidString).json") == true)
        #expect(WidgetSharedStore
            .isNewPadRequest(fileName: "pending-open-pad-\(ordinal)-\(UUID().uuidString).json") == false)
    }

    @Test
    func `anything else in the container is not a request`() {
        for name in ["recent-pads.json",
                     "widget-accounts.json",
                     "claimed-pending-new-pad-1.json",
                     "pending-new-pad-1.txt",
                     ""] {
            #expect(WidgetSharedStore.isNewPadRequest(fileName: name) == nil, "\(name) should not be a request")
        }
    }
}

@Suite("Widget shared container sweep (#2589, #2592, #2593, #2603)")
struct WidgetContainerSweepTests {
    private let live: Set<String> = ["AAAA-1", "BBBB-2"]

    @Test
    func `abandoned claims and quarantined payloads are swept once old`() {
        let claimed = "claimed-\(UUID().uuidString).json"
        let corrupt = "corrupt-\(UUID().uuidString).json"
        for name in [claimed, corrupt] {
            // Still within the window: the process that made it may yet finish.
            #expect(!WidgetSharedStore.shouldSweep(name: name, age: 60, liveAccountIDs: live))
            #expect(WidgetSharedStore.shouldSweep(
                name: name,
                age: WidgetSharedStore.abandonedClaimLifetime + 1,
                liveAccountIDs: live
            ))
        }
    }

    @Test
    func `undrained requests are swept only once stale`() {
        let name = "pending-new-pad-000000001700000000123-\(UUID().uuidString).json"
        #expect(!WidgetSharedStore.shouldSweep(name: name, age: 60, liveAccountIDs: live))
        #expect(WidgetSharedStore.shouldSweep(
            name: name,
            age: WidgetSharedStore.pendingRequestLifetime + 1,
            liveAccountIDs: live
        ))
    }

    @Test
    func `per-account files are swept when their account is gone`() {
        // Age is irrelevant here: an orphaned account file is orphaned immediately.
        #expect(WidgetSharedStore.shouldSweep(name: "recent-pads-GONE.json", age: 0, liveAccountIDs: live))
        #expect(WidgetSharedStore.shouldSweep(name: "widget-favorites-GONE.json", age: 0, liveAccountIDs: live))
        #expect(!WidgetSharedStore.shouldSweep(name: "recent-pads-AAAA-1.json", age: 0, liveAccountIDs: live))
        #expect(!WidgetSharedStore.shouldSweep(name: "widget-favorites-BBBB-2.json", age: 0, liveAccountIDs: live))
    }

    @Test
    func `the default snapshot and account index are never swept`() {
        // Neither is account-keyed, and deleting either would blank an unconfigured
        // widget or empty its configuration picker.
        for name in ["recent-pads.json", "widget-accounts.json"] {
            #expect(!WidgetSharedStore.shouldSweep(name: name, age: 10 * 365 * 24 * 60 * 60, liveAccountIDs: live))
        }
    }
}

@Suite("Pad activity URL canonicalization (#2690)")
struct PadActivityCanonicalURLTests {
    @Test
    func `a query and fragment are dropped`() throws {
        // Only the pad's identity is needed to resume it; the full URL was going into
        // Spotlight, Siri prediction, and Handoff metadata (#2690).
        let url = URL(string: "https://app.coderpad.io/abc12345?token=secret&utm=x#section")
        #expect(try PadActivity.canonicalPadURL(#require(url))?.absoluteString
            == "https://app.coderpad.io/abc12345")
    }

    @Test
    func `a plain pad URL is unchanged`() throws {
        let url = URL(string: "https://app.coderpad.io/abc12345")
        #expect(try PadActivity.canonicalPadURL(#require(url))?.absoluteString
            == "https://app.coderpad.io/abc12345")
    }

    @Test
    func `a known trailing page is kept`() throws {
        // A handed-off playback view should resume where it was.
        let url = URL(string: "https://app.coderpad.io/abc12345/playback?t=12")
        #expect(try PadActivity.canonicalPadURL(#require(url))?.absoluteString
            == "https://app.coderpad.io/abc12345/playback")
    }

    @Test
    func `a custom server keeps its port`() throws {
        let url = URL(string: "https://pads.example.com:8443/abc12345?x=1")
        #expect(try PadActivity.canonicalPadURL(#require(url))?.absoluteString
            == "https://pads.example.com:8443/abc12345")
    }

    @Test
    func `a non-pad route has no canonical form`() throws {
        #expect(try PadActivity.canonicalPadURL(#require(URL(string: "https://app.coderpad.io/login"))) == nil)
        #expect(try PadActivity.canonicalPadURL(#require(URL(string: "https://app.coderpad.io/admin"))) == nil)
        #expect(try PadActivity.canonicalPadURL(#require(URL(string: "https://app.coderpad.io/"))) == nil)
    }
}
