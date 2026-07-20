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
    }
}
