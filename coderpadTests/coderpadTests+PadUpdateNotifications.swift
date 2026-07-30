//
//  coderpadTests+PadUpdateNotifications.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing
import UserNotifications

private actor NotificationPostRecorder {
    var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}

@Suite("Pad update notification links")
struct PadUpdateNotificationLinkTests {
    @Test
    func `replacement notification work completes after its predecessor`() async {
        let recorder = NotificationPostRecorder()
        let predecessor = Task {
            try? await Task.sleep(for: .milliseconds(30))
            await recorder.append("old")
        }
        let replacement = Task {
            await PadUpdateNotifier.runAfterPredecessor(predecessor) {
                await recorder.append("new")
            }
        }

        await replacement.value

        #expect(await recorder.values == ["old", "new"])
    }

    @Test
    func `foreground delivery stays quiet`() {
        #expect(PadUpdateNotifier.presentationOptions(appIsActive: true).isEmpty)
        let background = PadUpdateNotifier.presentationOptions(appIsActive: false)
        #expect(background.contains(.banner))
        #expect(background.contains(.sound))
    }

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
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "com.adamdangoor.padbuddy://pad"))) == nil)
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "com.adamdangoor.padbuddy://pad/a/b"))) == nil)
        #expect(try CoderpadApp.padID(fromDeepLink: #require(URL(string: "com.adamdangoor.padbuddy://pad/%00"))) == nil)
    }

    @Test
    func `legacy pad links remain parseable during migration`() throws {
        let legacy = try #require(URL(string: "coderpad://pad/abc123"))
        #expect(CoderpadApp.padID(fromDeepLink: legacy) == "abc123")
    }

    @Test
    func `cleanup recognizes only pad-update notification identifiers`() {
        #expect(PadUpdateNotifier.isPadUpdateNotificationIdentifier("coderpad.padUpdates"))
        #expect(PadUpdateNotifier.isPadUpdateNotificationIdentifier("coderpad.padUpdates.account-id"))
        #expect(!PadUpdateNotifier.isPadUpdateNotificationIdentifier("coderpad.padUpdatesOther"))
        #expect(!PadUpdateNotifier.isPadUpdateNotificationIdentifier("coderpad.other"))
    }

    @Test
    func `multi-pad notification links retain their account scope`() throws {
        let accountID = UUID()
        let url = try #require(PadUpdateNotifier.padsNotificationURL(accountID: accountID))

        #expect(url.host == "pads")
        #expect(CoderpadApp.accountID(fromDeepLink: url) == accountID)
        #expect(try #require(PadUpdateNotifier.padsNotificationURL(accountID: nil)).absoluteString
            == "com.adamdangoor.padbuddy://pads")
    }
}
