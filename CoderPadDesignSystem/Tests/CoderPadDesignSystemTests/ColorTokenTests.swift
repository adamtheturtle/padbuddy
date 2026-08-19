@testable import CoderPadDesignSystem
import SwiftUI
import Testing

@Suite("Color tokens")
struct ColorTokenTests {
    @Test
    func `extended finite components are clamped to sRGB range`() {
        #expect(Color.hexString(red: 1.5, green: -0.25, blue: 0.5) == "#FF0080")
        #expect(Color(.sRGB, red: 1.5, green: -0.25, blue: 0.5).hexString == "#FF0080")
    }

    @Test(arguments: [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity])
    func `non-finite components are unrepresentable`(component: CGFloat) {
        #expect(Color.hexString(red: component, green: 0.5, blue: 0.5) == nil)
    }
}
