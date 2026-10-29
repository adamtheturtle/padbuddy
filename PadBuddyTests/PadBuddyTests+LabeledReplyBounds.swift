import Foundation
@testable import PadBuddy
import Testing

@Suite("Labeled model reply bounds")
struct LabeledReplyBoundsTests {
    @Test func `oversized model reply is rejected instead of parsed into draft fields`() {
        let reply = "TITLE: Interview\nSOLUTION: "
            + String(repeating: "x", count: OnDeviceModelParsing.maximumLabeledReplyBytes)
        #expect(OnDeviceModelParsing.labeledSections(reply, labels: ["TITLE", "SOLUTION"]).isEmpty)
    }

    @Test func `oversized sections and excessive lines are rejected`() {
        let oversizedSection = "TITLE: Interview\nSOLUTION: "
            + String(repeating: "x", count: OnDeviceModelParsing.maximumLabeledSectionBytes + 1)
        #expect(OnDeviceModelParsing.labeledSections(oversizedSection, labels: ["TITLE", "SOLUTION"]).isEmpty)
        let excessiveLines = "TITLE: Interview\nSOLUTION: code\n"
            + String(repeating: "\n", count: OnDeviceModelParsing.maximumLabeledLines)
        #expect(OnDeviceModelParsing.labeledSections(excessiveLines, labels: ["TITLE", "SOLUTION"]).isEmpty)
    }
}
