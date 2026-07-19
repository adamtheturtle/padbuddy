//
//  LayoutMeasurementTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import CoreGraphics
import Testing

@Suite("Layout measurement bounds")
struct LayoutMeasurementTests {
    @Test
    func `sidebar preference never exceeds its cap`() {
        var width: CGFloat = 40
        SidebarRowWidthKey.reduce(value: &width) { 10000 }
        #expect(width == SidebarRowWidthKey.maximumValue)
    }

    @Test
    func `sidebar measurement truncates by grapheme cluster`() {
        let family = "👨‍👩‍👧‍👦"
        let bounded = SidebarRowWidthKey.boundedLabel(
            String(repeating: family, count: SidebarRowWidthKey.maximumLabelLength + 20)
        )

        #expect(bounded.count == SidebarRowWidthKey.maximumLabelLength)
        #expect(bounded.last == Character(family))
    }
}
