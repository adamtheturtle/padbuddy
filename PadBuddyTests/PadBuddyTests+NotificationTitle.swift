import Foundation
@testable import PadBuddy
import Testing

@Suite("Notification title presentation")
struct NotificationTitleTests {
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
