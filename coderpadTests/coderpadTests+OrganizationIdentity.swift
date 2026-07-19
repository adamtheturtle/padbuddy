@testable import CoderPad
import Testing

@Suite("Organization validation identity")
@MainActor
struct OrganizationIdentityTests {
    @Test(arguments: ["", "   ", "\n"])
    func `blank organization names are rejected`(name: String) {
        #expect(!AccountEditor.hasUsableOrganizationIdentity(name: name, userEmails: ["owner@example.com"]))
    }

    @Test
    func `organizations require at least one plausible member`() {
        #expect(!AccountEditor.hasUsableOrganizationIdentity(name: "Acme", userEmails: []))
        #expect(!AccountEditor.hasUsableOrganizationIdentity(name: "Acme", userEmails: ["invalid", "   "]))
        #expect(AccountEditor.hasUsableOrganizationIdentity(name: "Acme", userEmails: ["owner@example.com"]))
    }

    @Test
    func `member search keys fold case and diacritics once`() {
        #expect(OrganizationView.normalizedSearchKey("René@Example.COM").contains("rene@example.com"))
    }
}
