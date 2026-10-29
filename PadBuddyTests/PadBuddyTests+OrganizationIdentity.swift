import Foundation
@testable import PadBuddy
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

    @Test func `member preparation rejects oversized and control bearing identities`() throws {
        let data = try JSONSerialization.data(withJSONObject: ["users": [
            ["email": String(repeating: "x", count: 10000), "name": "Oversized"],
            ["email": "bad\n@example.com", "name": "Injected"],
            ["email": "z@example.com", "name": "Z" + String(repeating: "x", count: 10000)],
            ["email": "a@example.com", "name": "Alice"],
            ["email": "A@EXAMPLE.COM", "name": "Duplicate"]
        ]])
        let organization = try JSONDecoder().decode(Organization.self, from: data)
        let users = OrganizationView.preparedUsers(organization)
        #expect(users.map(\.email) == ["a@example.com", "z@example.com"])
        #expect(OrganizationUserPresentation(user: users[1]).name.count == 120)
    }

    @Test
    func `organization user presentation removes controls and bounds copied values`() throws {
        let user = try JSONDecoder().decode(
            OrganizationUser.self,
            from: Data(#"{"name":"Alice\nInjected\u0000Name","email":"owner\r@example.com"}"#.utf8)
        )

        let presentation = OrganizationUserPresentation(user: user)

        #expect(presentation.name == "Alice Injected Name")
        #expect(presentation.email == "owner @example.com")
        #expect(presentation.copyName == presentation.name)
        #expect(presentation.copyEmail == presentation.email)
        #expect(!presentation.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        #expect(!presentation.email.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
    }

    @Test
    func `organization user presentation caps remote fields`() throws {
        let name = String(repeating: "N", count: 200)
        let email = String(repeating: "e", count: 300)
        let data = try JSONSerialization.data(withJSONObject: ["name": name, "email": email])
        let presentation = try OrganizationUserPresentation(
            user: JSONDecoder().decode(OrganizationUser.self, from: data)
        )

        #expect(presentation.name.count == OrganizationUserPresentation.maximumNameLength)
        #expect(presentation.email.count == OrganizationUserPresentation.maximumEmailLength)
    }

    @Test
    func `blank organization user name falls back safely`() throws {
        let user = try JSONDecoder().decode(
            OrganizationUser.self,
            from: Data(#"{"name":" \n ","email":"owner@example.com"}"#.utf8)
        )

        let presentation = OrganizationUserPresentation(user: user)

        #expect(presentation.name == "owner@example.com")
        #expect(presentation.copyName == nil)
    }
}
