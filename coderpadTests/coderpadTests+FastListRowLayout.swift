@testable import CoderPad
import Testing

@Suite("FastList row layout")
struct FastListRowLayoutTests {
    @Test
    func `regular width keeps comfortable row insets`() {
        let insets = FastListRowInsetPolicy.horizontal(compact: false, accessibilitySize: false)

        #expect(insets.leading == 32)
        #expect(insets.trailing == 24)
    }

    @Test
    func `compact width returns space to row content`() {
        let insets = FastListRowInsetPolicy.horizontal(compact: true, accessibilitySize: false)

        #expect(insets.leading == 20)
        #expect(insets.trailing == 16)
    }

    @Test(arguments: [false, true])
    func `accessibility text gets the most content width`(compact: Bool) {
        let insets = FastListRowInsetPolicy.horizontal(compact: compact, accessibilitySize: true)

        #expect(insets.leading == 16)
        #expect(insets.trailing == 12)
    }
}
