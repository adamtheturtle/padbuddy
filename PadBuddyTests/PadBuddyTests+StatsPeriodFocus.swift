@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Stats period focus")
struct StatsPeriodFocusTests {
    @Test
    func `independent bindings do not retarget each other`() {
        var first = StatsPeriod.days7
        var second = StatsPeriod.days30
        let firstBinding = Binding(get: { first }, set: { first = $0 })
        let secondBinding = Binding(get: { second }, set: { second = $0 })

        firstBinding.wrappedValue = .days90

        #expect(first == .days90)
        #expect(secondBinding.wrappedValue == .days30)
    }
}
