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

    private func decode(_ count: Int) throws -> OrganizationStats {
        let data = try JSONSerialization.data(withJSONObject: ["pads_created": count, "users": []])
        return try JSONDecoder().decode(OrganizationStats.self, from: data)
    }
}
