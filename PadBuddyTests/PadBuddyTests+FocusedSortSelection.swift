@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Focused sort selection")
struct FocusedSortSelectionTests {
    @Test
    func `independent list bindings do not retarget another scene`() {
        var first = PadSort.updatedDesc
        var second = PadSort.createdDesc
        let firstBinding = Binding(get: { first }, set: { first = $0 })
        let secondBinding = Binding(get: { second }, set: { second = $0 })

        firstBinding.wrappedValue = .titleAsc

        #expect(first == .titleAsc)
        #expect(secondBinding.wrappedValue == .createdDesc)
    }
}
