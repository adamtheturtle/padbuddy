//
//  LayoutMeasurementTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import CoreGraphics
import SwiftUI
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

    @Test
    func `sidebar measurement context changes with rendering environment`() {
        let baseline = SidebarMeasurementContext(
            dynamicTypeSize: .medium,
            localeIdentifier: "en_GB",
            layoutDirection: .leftToRight
        )

        #expect(baseline != SidebarMeasurementContext(
            dynamicTypeSize: .accessibility1,
            localeIdentifier: "en_GB",
            layoutDirection: .leftToRight
        ))
        #expect(baseline != SidebarMeasurementContext(
            dynamicTypeSize: .medium,
            localeIdentifier: "ar",
            layoutDirection: .leftToRight
        ))
        #expect(baseline != SidebarMeasurementContext(
            dynamicTypeSize: .medium,
            localeIdentifier: "en_GB",
            layoutDirection: .rightToLeft
        ))
    }
}
