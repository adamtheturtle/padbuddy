import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen status presentation normalization")
struct ScreenStatusPresentationTests {
    @Test(arguments: ["completed", " Completed \n", "COMPLETED"])
    func `completed variants share filter label color and completion date`(_ status: String) throws {
        #expect(ScreenTestStatusPolicy.normalized(status) == "completed")
        #expect(ScreenTestStatus.label(status) == ScreenTestStatus.label("completed"))
        #expect(ScreenTestStatus.color(status) == .green)
        let session = try ScreenTestSession(id: 1, status: status, endTime: 1_700_000_000_000)
        let canonical = try ScreenTestSession(id: 1, status: "completed", endTime: 1_700_000_000_000)
        #expect(ScreenTestRow(test: session).dateText == ScreenTestRow(test: canonical).dateText)
    }
}
