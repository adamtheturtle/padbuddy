//
//  FlowLayoutTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Testing

@Suite("FlowLayout spacing")
struct FlowLayoutTests {
    @Test
    func `spacing is normalized to a nonnegative value`() {
        #expect(normalizedFlowSpacing(-8) == 0)
        #expect(normalizedFlowSpacing(0) == 0)
        #expect(normalizedFlowSpacing(12) == 12)
        #expect(normalizedFlowSpacing(.nan) == 0)
        #expect(normalizedFlowSpacing(.infinity) == 0)
        #expect(normalizedFlowSpacing(-.infinity) == 0)
        #expect(normalizedFlowSpacing(maximumFlowSpacing + 1) == maximumFlowSpacing)
    }
}
