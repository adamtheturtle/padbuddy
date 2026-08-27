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

@Suite("Screen breakdown name bounds (#4578)")
struct ScreenBreakdownNameBoundTests {
    @Test func `a short name is shown whole`() {
        #expect(screenBreakdownLabel("Python") == "Python")
    }

    @Test func `an overlong name is bounded and marked as truncated`() {
        let name = String(repeating: "x", count: 4096)

        let label = screenBreakdownLabel(name)

        #expect(label.count == ScreenBreakdownLimits.nameCharacters + 1)
        #expect(label.hasSuffix("…"))
    }

    @Test func `visible names still respect the count limit`() {
        let values = Dictionary(uniqueKeysWithValues: (0 ..< 100).map { ("tech-\($0)", $0) })

        #expect(visibleScreenBreakdownNames(values, limit: 25).count == 25)
    }

    @Test func `names sharing a bounded prefix all remain reachable`() {
        // Sorting on the bounded prefix must not collapse distinct keys.
        let long = String(repeating: "a", count: ScreenBreakdownLimits.nameCharacters + 10)
        let values = [long: 1, long + "b": 2, "z": 3]

        let names = visibleScreenBreakdownNames(values, limit: 25)

        #expect(Set(names) == Set(values.keys))
    }
}
