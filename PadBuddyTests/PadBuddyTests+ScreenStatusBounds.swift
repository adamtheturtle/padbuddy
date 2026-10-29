import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen status presentation bounds")
struct ScreenStatusBoundsTests {
    @Test func `unknown status keys and labels are bounded before transformation`() {
        let remote = String(repeating: "unknown_status_", count: 100_000)
        let key = ScreenTestStatusPolicy.normalized(remote)
        #expect(key.unicodeScalars.count <= ScreenTestStatusPolicy.maximumKeyScalars)
        #expect(ScreenTestStatus.label(remote).count <= ScreenTestStatus.maximumUnknownLabelLength)
        #expect(ScreenTestStatusPolicy.normalized(key) == key)
    }

    @Test func `status presentation removes unsafe formatting and normalizes known variants`() {
        #expect(ScreenTestStatusPolicy.normalized("\nCOMPLETED\u{202E}") == "completed")
        #expect(ScreenTestStatus.label("\nCOMPLETED\u{202E}") == ScreenTestStatus.label("completed"))
        #expect(ScreenTestStatus.label("\n\u{202E}") == String(localized: "Unknown"))
    }
}
