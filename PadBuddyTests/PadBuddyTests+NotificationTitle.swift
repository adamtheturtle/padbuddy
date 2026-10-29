import Foundation
@testable import PadBuddy
import Testing

@Suite("Notification title presentation")
struct NotificationTitleTests {
    @Test func `notification payloads retain bounded metadata and account scoped destinations`() throws {
        let pad = try JSONDecoder().decode(Pad.self, from: Data(#"{"id":"abc123","title":"Secret candidate"}"#.utf8))
        let account = UUID()
        let single = PadUpdateNotifier.notificationPayload(
            changes: [PadChange(pad: pad, kind: .new)], accountID: account
        )
        #expect(single.title == "Secret candidate")
        let singleURL = try #require(single.url.flatMap(URL.init(string:)))
        #expect(PadBuddyApp.padID(fromDeepLink: singleURL) == pad.id)
        #expect(PadBuddyApp.accountID(fromDeepLink: singleURL) == account)
        let burst = PadUpdateNotifier.notificationPayload(
            changes: [PadChange(pad: pad, kind: .new), PadChange(pad: pad, kind: .ended)], accountID: account
        )
        #expect(burst.count == 2)
        #expect(!burst.title.contains("Secret"))
        #expect(!burst.body.contains("Secret"))
        let burstURL = try #require(burst.url.flatMap(URL.init(string:)))
        #expect(burstURL.host == "pads")
        #expect(PadBuddyApp.accountID(fromDeepLink: burstURL) == account)
    }

    @Test func `remote notification titles are bounded before display`() {
        let remote = String(repeating: "😀", count: 1_000_000)
        let title = PadUpdateNotifier.notificationPadTitle(remote)
        #expect(title.unicodeScalars.count == PadUpdateNotifier.maximumTitleScalars)
        #expect(title == String(repeating: "😀", count: PadUpdateNotifier.maximumTitleScalars))
    }

    @Test func `notification titles are single line and format safe`() {
        #expect(PadUpdateNotifier.notificationPadTitle("  Alice\n\tInterview\u{202E} title  ")
            == "Alice Interview title")
        #expect(PadUpdateNotifier.notificationPadTitle("\n\t\u{202E}") == String(localized: "Untitled pad"))
        #expect(PadUpdateNotifier.notificationPadTitle("面接") == "面接")
    }
}
