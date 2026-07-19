@testable import CoderPad
import Foundation
import Testing

@Suite("Organization validation identity")
@MainActor
struct OrganizationIdentityTests {
    @Test
    func `validated organization membership follows the selected email`() throws {
        let users = try JSONDecoder().decode(
            [OrganizationUser].self,
            from: Data(#"[{"name":"Owner","email":"Owner@example.com"}]"#.utf8)
        )

        #expect(AccountEditor.emailBelongsToValidatedOrganization(" owner@EXAMPLE.com ", users: users))
        #expect(!AccountEditor.emailBelongsToValidatedOrganization("other@example.com", users: users))
        #expect(!AccountEditor.emailBelongsToValidatedOrganization("not-an-email", users: users))
    }

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
