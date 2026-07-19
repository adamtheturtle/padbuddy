@testable import CoderPad
import Testing

@Suite("Account demo magic")
@MainActor
struct AccountDemoMagicTests {
    @Test
    func `magic keys are accepted only while adding`() {
        #expect(AccountEditor.demoMagicKey(typedKey: "demo", isEditing: false) != nil)
        #expect(AccountEditor.demoMagicKey(typedKey: "baddemo", isEditing: false) != nil)
        #expect(AccountEditor.demoMagicKey(typedKey: "demo", isEditing: true) == nil)
        #expect(AccountEditor.demoMagicKey(typedKey: "baddemo", isEditing: true) == nil)
    }
}
