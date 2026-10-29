import Foundation
@testable import PadBuddy
import Testing

@Suite("Organization count quality")
struct OrganizationCountQualityTests {
    @Test(arguments: [-1, Int.min, 1_000_000_001, Int.max])
    func `unsupported remote counts are not credible`(_ count: Int) {
        #expect(!OrganizationCountQuality.isSupported(count))
    }

    @Test(arguments: [0, 1, 1_000_000_000])
    func `supported statistics remain available`(_ count: Int) throws {
        let stats = try decode(count)
        #expect(OrganizationCountQuality.validatedStats(stats) == stats)
    }

    @Test func `schema valid extreme statistics are unavailable rather than presented as totals`() throws {
        let stats = try decode(Int.max)
        #expect(OrganizationCountQuality.validatedStats(stats) == nil)
        #expect(OrganizationCountQuality.validatedStats(nil) == nil)
    }

    @Test(arguments: [0, 1, Int.max])
    func `contradictory or extreme reported member totals are unavailable`(_ reported: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "user_count": reported, "users": [["email": "a@example.com"], ["email": "b@example.com"]]
        ])
        let org = try JSONDecoder().decode(Organization.self, from: data)
        #expect(OrganizationCountQuality.memberCount(in: org) == nil)
    }

    @Test(arguments: [2, 3, 1_000_000_000])
    func `credible reported totals may include members outside the returned slice`(_ reported: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "user_count": reported, "users": [["email": "a@example.com"], ["email": "b@example.com"]]
        ])
        let org = try JSONDecoder().decode(Organization.self, from: data)
        #expect(OrganizationCountQuality.memberCount(in: org) == reported)
    }

    @Test func `absent reported counts use the loaded membership`() throws {
        let data = Data(#"{"users":[{"email":"a@example.com"}]}"#.utf8)
        let org = try JSONDecoder().decode(Organization.self, from: data)
        #expect(OrganizationCountQuality.memberCount(in: org) == 1)
    }

    private func decode(_ count: Int) throws -> OrganizationStats {
        let data = try JSONSerialization.data(withJSONObject: ["pads_created": count, "users": []])
        return try JSONDecoder().decode(OrganizationStats.self, from: data)
    }
}
