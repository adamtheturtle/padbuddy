import Foundation
@testable import PadBuddy
import Testing

@Suite("Organization member window")
struct OrganizationMemberWindowTests {
    @Test func `member preparation caps input before deduplication and sorting`() throws {
        let users = (1 ... 10000).map { ["email": "member\($0)@example.com", "name": "Member \($0)"] }
        let data = try JSONSerialization.data(withJSONObject: ["users": users])
        let org = try JSONDecoder().decode(Organization.self, from: data)
        let prepared = OrganizationView.preparedUsers(org)
        #expect(prepared.count == OrganizationMemberWindow.maximumRecords)
        #expect(!prepared.contains { $0.email == "member1001@example.com" })
        #expect(org.users.count - prepared.count == 9000)
    }

    @Test func `duplicate records do not cause a scan beyond the retained input window`() throws {
        var users = Array(repeating: ["email": "same@example.com"], count: 1000)
        users.append(["email": "outside@example.com"])
        let data = try JSONSerialization.data(withJSONObject: ["users": users])
        let org = try JSONDecoder().decode(Organization.self, from: data)
        #expect(OrganizationView.preparedUsers(org).map(\.email) == ["same@example.com"])
    }
}
