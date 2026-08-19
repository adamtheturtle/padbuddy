import AppKit
@testable import CoderPadDesignSystem
import Testing

@Suite("Focus ring suppressor")
struct FocusRingSuppressorTests {
    @Test
    func `only the nearest backing control loses its focus ring`() {
        let ancestor = NSButton()
        ancestor.focusRingType = .exterior
        ancestor.cell?.focusRingType = .exterior
        let backingControl = NSButton()
        backingControl.focusRingType = .exterior
        backingControl.cell?.focusRingType = .exterior
        let marker = NSView()
        ancestor.addSubview(backingControl)
        backingControl.addSubview(marker)

        FocusRingSuppressor.suppress(from: marker)

        #expect(backingControl.focusRingType == .none)
        #expect(backingControl.cell?.focusRingType == NSFocusRingType.none)
        #expect(ancestor.focusRingType == .exterior)
        #expect(ancestor.cell?.focusRingType == .exterior)
    }
}
