@testable import CoderPad
import Testing

@Suite("Settings add account protection")
struct SettingsAddAccountProtectionTests {
    @Test
    func `dirty saved account requires discard confirmation`() {
        #expect(SettingsView.addAccountRequestNeedsDiscardConfirmation(savedAccountEditDirty: true))
        #expect(!SettingsView.addAccountRequestNeedsDiscardConfirmation(savedAccountEditDirty: false))
    }
}
