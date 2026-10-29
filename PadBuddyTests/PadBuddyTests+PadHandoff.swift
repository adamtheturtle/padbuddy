//
//  PadBuddyTests+PadHandoff.swift
//  PadBuddyTests
//
//  Tests for incoming pad Handoff activity URL validation.
//

// swiftlint:disable file_length

import AppGroupMailbox
import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad Handoff activity URLs")
@MainActor
struct PadHandoffTests {
    @Test
    func `repeated playback suffixes are rejected in both directions`() throws {
        let url = try #require(URL(string: "https://app.coderpad.io/ABC123/playback/playback"))
        let activity = NSUserActivity(activityType: PadActivity.type)
        activity.webpageURL = url
        #expect(padActivityURL(activity) == nil)
        #expect(PadActivity.canonicalPadURL(url) == nil)
    }

    @Test
    func `invalid origins retain their validation failure`() throws {
        let url = try #require(URL(string: "file:///tmp/not-a-pad"))
        #expect(throws: (any Error).self) {
            _ = try PadActivity.validatedOrigin(of: url)
        }
        #expect(PadActivity.origin(of: url) == nil)
    }

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
            "com.adamdangoor.padbuddy://pad/ABC123",
            "https://app.coderpad.io"
        ] {
            let activity = NSUserActivity(activityType: PadActivity.type)
            if raw.hasPrefix("http") {
                activity.webpageURL = URL(string: raw)
            } else {
                activity.addUserInfoEntries(from: [PadActivity.urlKey: raw])
            }

            #expect(padActivityURL(activity) == nil, "\(raw) should be rejected")
        }
    }
}

@Suite("Widget handoff request ordering (#2590, #2591)")
struct WidgetHandoffOrderingTests {
    @Test
    func `quarantine trimming keeps newest files regardless of random name order`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetHandoffTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldest = directory.appendingPathComponent("legacy-quarantine-z.bin")
        let middle = directory.appendingPathComponent("legacy-quarantine-a.bin")
        let newest = directory.appendingPathComponent("legacy-quarantine-m.bin")
        for file in [oldest, middle, newest] {
            try Data().write(to: file)
        }
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30)], ofItemAtPath: oldest.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-20)], ofItemAtPath: middle.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: newest.path
        )

        WidgetSharedStore.trimLegacyQuarantine(in: directory, limit: 2)

        #expect(!FileManager.default.fileExists(atPath: oldest.path))
        #expect(FileManager.default.fileExists(atPath: middle.path))
        #expect(FileManager.default.fileExists(atPath: newest.path))
    }

    @Test
    func `drain leaves the eleventh valid request pending`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetHandoffTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mailbox = try AppGroupMailbox<WidgetPendingRequest>(
            containerURL: directory,
            namespace: "batch-test"
        )
        for index in 0 ..< 11 {
            try mailbox.enqueue(.openPad(WidgetOpenPadRequest(id: "pad-\(index)", account: nil)))
        }

        let first = WidgetSharedStore.takePendingRequestsInOrder(from: mailbox)
        #expect(openPadIDs(first) == (0 ..< 10).map { "pad-\($0)" })
        for request in first {
            try request.acknowledge()
        }
        let second = WidgetSharedStore.takePendingRequestsInOrder(from: mailbox)
        #expect(openPadIDs(second) == ["pad-10"])
    }

    @Test
    func `legacy handoff read stays on its validated descriptor`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetHandoffTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("request.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data("original".utf8)
        try original.write(to: file)

        let read = WidgetSharedStore.safeLegacyData(at: file) {
            try? Data(repeating: 0x78, count: WidgetSharedStore.maxRequestFileBytes + 1)
                .write(to: file, options: .atomic)
        }

        #expect(read == original)
    }

    @Test
    func `duplicate new-pad request identities drain only once`() {
        let id = UUID()
        let duplicate = WidgetNewPadRequest(account: nil, question: nil, id: id)
        let unique = WidgetNewPadRequest(account: nil, question: nil)
        let requests: [WidgetPendingRequest] = [
            .newPad(duplicate),
            .openPad(WidgetOpenPadRequest(id: "pad-1", account: nil)),
            .newPad(duplicate),
            .newPad(unique)
        ]

        let deduplicated = WidgetSharedStore.deduplicatingNewPadRequests(requests)
        #expect(deduplicated.count == 3)
    }

    private func openPadIDs(_ requests: [WidgetClaimedRequest]) -> [String] {
        requests.compactMap { request in
            guard case let .openPad(openPad) = request.request else { return nil }

            return openPad.id
        }
    }

    @Test
    func `legacy new-pad requests gain an identity when decoded`() throws {
        let request = try JSONDecoder().decode(
            WidgetNewPadRequest.self,
            from: Data(#"{"account":null,"question":null}"#.utf8)
        )
        #expect(request.id.uuidString.count == 36)
    }

    @Test
    func `open-pad handoffs accept only URL-safe pad identifiers`() {
        #expect(WidgetSharedStore.validatedHandoffPadID(" ABC-123_test ") == "ABC-123_test")
        for malformed in ["", "pads/ABC", "ABC?next=1", "ABC#fragment", "ABC.123", String(repeating: "A", count: 65)] {
            #expect(WidgetSharedStore.validatedHandoffPadID(malformed) == nil)
        }
    }

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

    @Test
    func `legacy filenames have stable distinct migration identities`() {
        let first = WidgetSharedStore.legacyMigrationID(fileName: "pending-new-pad.json")
        #expect(first == WidgetSharedStore.legacyMigrationID(fileName: "pending-new-pad.json"))
        #expect(first != WidgetSharedStore.legacyMigrationID(fileName: "pending-open-pad.json"))
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

    @Test
    func `typed claims preserve kind and ordering for crash recovery`() {
        let ordinal = String(format: "%018llu", UInt64(1_700_000_000_123))
        let original = "pending-open-pad-\(ordinal)-\(UUID().uuidString).json"
        let claimed = "claimed-\(UUID().uuidString)-\(original)"

        #expect(WidgetSharedStore.claimedRequestOriginalName(claimed) == original)
        #expect(WidgetSharedStore.abandonedClaimOriginalName(
            fileName: claimed, age: WidgetSharedStore.abandonedClaimLifetime
        ) == nil)
        #expect(WidgetSharedStore.abandonedClaimOriginalName(
            fileName: claimed, age: WidgetSharedStore.abandonedClaimLifetime + 1
        ) == original)
        #expect(WidgetSharedStore.requestOrdinal(fileName: original) == 1_700_000_000_123)
    }

    @Test
    func `legacy opaque claims cannot be replayed as the wrong action`() {
        let opaque = "claimed-\(UUID().uuidString).json"
        #expect(WidgetSharedStore.claimedRequestOriginalName(opaque) == nil)
        #expect(WidgetSharedStore.abandonedClaimOriginalName(
            fileName: opaque, age: WidgetSharedStore.abandonedClaimLifetime + 1
        ) == nil)
    }
}

@Suite("Legacy widget handoff migration (#4162)")
struct LegacyWidgetHandoffMigrationTests {
    @Test
    func `pending requests migrate in issue order and a retry does not duplicate them`() throws {
        let fixture = try LegacyMigrationFixture()
        let early = "pending-new-pad-000000000000000001-\(UUID().uuidString).json"
        let late = "pending-open-pad-000000000000000002-\(UUID().uuidString).json"
        let account = UUID().uuidString
        try fixture.write(WidgetNewPadRequest(account: account, question: 42), named: early)
        try fixture.write(WidgetOpenPadRequest(id: "pad-2", account: nil), named: late)

        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)
        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)

        let claims = try fixture.mailbox.claimPending()
        #expect(claims.count == 2)
        guard claims.count == 2 else { return }

        if case let .newPad(request) = claims[0].message {
            #expect(request.question == 42)
            #expect(request.account == account)
        } else {
            Issue.record("The earlier New Pad request should migrate first")
        }
        if case let .openPad(request) = claims[1].message {
            #expect(request.id == "pad-2")
        } else {
            Issue.record("The later Open Pad request should migrate second")
        }
    }

    @Test
    func `an abandoned typed claim is recovered but a recent one is left alone`() throws {
        let fixture = try LegacyMigrationFixture()
        let original = "pending-open-pad-000000000000000003-\(UUID().uuidString).json"
        let abandoned = "claimed-\(UUID().uuidString)-\(original)"
        try fixture.write(WidgetOpenPadRequest(id: "old", account: nil), named: abandoned)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -WidgetSharedStore.abandonedClaimLifetime - 1)],
            ofItemAtPath: fixture.root.appendingPathComponent(abandoned).path
        )
        let recentOriginal = "pending-open-pad-000000000000000004-\(UUID().uuidString).json"
        let recent = "claimed-\(UUID().uuidString)-\(recentOriginal)"
        try fixture.write(WidgetOpenPadRequest(id: "recent", account: nil), named: recent)

        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)

        #expect(try fixture.mailbox.claimPending().map(\.message).count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(recent).path))
    }

    @Test
    func `expired pending request is removed without migration`() throws {
        let fixture = try LegacyMigrationFixture()
        let name = "pending-new-pad-000000000000000005-\(UUID().uuidString).json"
        try fixture.write(WidgetNewPadRequest(account: nil, question: nil), named: name)
        try fixture.age(name, by: WidgetSharedStore.legacyRequestLifetime + 1)

        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)

        #expect(try fixture.mailbox.claimPending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(name).path))
    }

    @Test
    func `future-dated legacy requests expire immediately (#4645)`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(365 * 24 * 60 * 60)
        #expect(WidgetSharedStore.legacyRequestIsExpired(modifiedAt: future, now: now))

        let skew = now.addingTimeInterval(WidgetSharedStore.futureModificationTolerance - 1)
        #expect(!WidgetSharedStore.legacyRequestIsExpired(modifiedAt: skew, now: now))
    }

    @Test
    func `expired abandoned claim is removed without recovery`() throws {
        let fixture = try LegacyMigrationFixture()
        let original = "pending-open-pad-000000000000000006-\(UUID().uuidString).json"
        let claimed = "claimed-\(UUID().uuidString)-\(original)"
        try fixture.write(WidgetOpenPadRequest(id: "stale", account: nil), named: claimed)
        try fixture.age(claimed, by: WidgetSharedStore.legacyRequestLifetime + 1)

        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)

        #expect(try fixture.mailbox.claimPending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(claimed).path))
    }

    @Test
    func `malformed oversized and symbolic legacy inputs are quarantined`() throws {
        let fixture = try LegacyMigrationFixture()
        try Data("not-json".utf8).write(
            to: fixture.root.appendingPathComponent("pending-new-pad-000000000000000001-bad.json")
        )
        try Data(repeating: 0, count: WidgetSharedStore.maxRequestFileBytes + 1).write(
            to: fixture.root.appendingPathComponent("pending-open-pad-000000000000000002-large.json")
        )
        let outside = fixture.root.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("pending-open-pad-000000000000000003-link.json"),
            withDestinationURL: outside
        )

        WidgetSharedStore.migrateLegacyRequests(in: fixture.root, mailbox: fixture.mailbox)

        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        #expect(names.filter { $0.hasPrefix("legacy-quarantine-") }.count == 3)
        #expect(try fixture.mailbox.claimPending().isEmpty)
    }
}

private final class LegacyMigrationFixture {
    let root: URL
    let mailbox: AppGroupMailbox<WidgetPendingRequest>

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoderPadLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        mailbox = try AppGroupMailbox(
            containerURL: root,
            namespace: "widget-actions",
            limits: .init(maxMessages: 100, maxPayloadBytes: WidgetSharedStore.maxRequestFileBytes)
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ value: some Encodable, named name: String) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name))
    }

    func age(_ name: String, by interval: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -interval)],
            ofItemAtPath: root.appendingPathComponent(name).path
        )
    }
}

@Suite("Widget shared container sweep (#2603)")
struct WidgetContainerSweepTests {
    private let live: Set<String> = ["AAAA-1", "BBBB-2"]

    @Test
    func `per-account files are swept when their account is gone`() {
        // Age is irrelevant here: an orphaned account file is orphaned immediately.
        #expect(WidgetSharedStore.shouldSweep(name: "recent-pads-GONE.json", liveAccountIDs: live))
        #expect(WidgetSharedStore.shouldSweep(name: "widget-favorites-GONE.json", liveAccountIDs: live))
        #expect(!WidgetSharedStore.shouldSweep(name: "recent-pads-AAAA-1.json", liveAccountIDs: live))
        #expect(!WidgetSharedStore.shouldSweep(name: "widget-favorites-BBBB-2.json", liveAccountIDs: live))
    }

    @Test
    func `the default snapshot and account index are never swept`() {
        // Neither is account-keyed, and deleting either would blank an unconfigured
        // widget or empty its configuration picker.
        for name in ["recent-pads.json", "widget-accounts.json"] {
            #expect(!WidgetSharedStore.shouldSweep(name: name, liveAccountIDs: live))
        }
    }

    @Test
    func `legacy corrupt handoffs have bounded retention`() {
        let id = UUID().uuidString
        for name in ["corrupt-\(id).json", "corrupt-overflow-\(id).json"] {
            #expect(!WidgetSharedStore.shouldSweep(
                name: name,
                liveAccountIDs: live,
                age: WidgetSharedStore.abandonedClaimLifetime
            ))
            #expect(WidgetSharedStore.shouldSweep(
                name: name,
                liveAccountIDs: live,
                age: WidgetSharedStore.abandonedClaimLifetime + 1
            ))
        }
    }

    @Test
    func `future-dated legacy corrupt handoffs expire beyond ordinary clock skew`() {
        let name = "corrupt-\(UUID().uuidString).json"

        #expect(!WidgetSharedStore.shouldSweep(
            name: name,
            liveAccountIDs: live,
            age: -WidgetSharedStore.futureModificationTolerance
        ))
        #expect(WidgetSharedStore.shouldSweep(
            name: name,
            liveAccountIDs: live,
            age: -WidgetSharedStore.futureModificationTolerance - 1
        ))
    }

    @Test
    func `unrelated corrupt-prefixed files are never swept`() {
        for name in ["corrupt-report.json", "corrupt-notes.txt", "corrupt-overflow-not-a-uuid.json"] {
            #expect(!WidgetSharedStore.shouldSweep(
                name: name,
                liveAccountIDs: live,
                age: WidgetSharedStore.abandonedClaimLifetime * 10
            ))
        }
    }
}

@Suite("Pad activity URL canonicalization (#2690)")
struct PadActivityCanonicalURLTests {
    @Test(arguments: ["admin", "unknown", "playback/unknown"])
    func `unknown trailing pages have no canonical form`(_ suffix: String) throws {
        let url = try #require(URL(string: "https://app.coderpad.io/ABC123/\(suffix)?token=secret"))
        #expect(PadActivity.canonicalPadURL(url) == nil)
    }

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
