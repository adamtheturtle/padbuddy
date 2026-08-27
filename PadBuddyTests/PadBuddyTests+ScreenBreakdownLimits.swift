//
//  PadBuddyTests+ScreenBreakdownLimits.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen breakdown presentation limits")
struct ScreenBreakdownLimitTests {
    @Test
    func `visible breakdown names are sorted and bounded`() {
        let values = Dictionary(uniqueKeysWithValues: (0 ..< 40).map { (String(format: "%02d", $0), $0) })

        let visible = visibleScreenBreakdownNames(values, limit: ScreenBreakdownLimits.technologies)

        #expect(visible.count == ScreenBreakdownLimits.technologies)
        #expect(visible == visible.sorted())
        #expect(visible.first == "00")
        #expect(visible.last == "24")
    }
}
