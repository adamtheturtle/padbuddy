//
//  coderpadTests+QuotaPace.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Quota pace projection")
struct QuotaPaceProjectionTests {
    private func quota(used: Int, limit: Int, overagesEnabled: Bool = false) throws -> Quota {
        let reset = Date().addingTimeInterval(24 * 60 * 60)
        let iso = ISO8601DateFormatter().string(from: reset)
        let data = try JSONSerialization.data(withJSONObject: [
            "pads_used": used, "billing_cycle_pad_limit": limit, "quota_reset_at": iso,
            "overages_enabled": overagesEnabled
        ])
        return try CoderPadClient.decoder.decode(Quota.self, from: data)
    }

    private func pace(used: Int, limit: Int, overagesEnabled: Bool = false) throws -> QuotaPace {
        let now = Date()
        return try #require(QuotaPace(
            quota: quota(used: used, limit: limit, overagesEnabled: overagesEnabled),
            cycleStart: now.addingTimeInterval(-29 * 24 * 60 * 60),
            now: now
        ))
    }

    @Test
    func `quota without an authoritative cycle start has no pace`() throws {
        let decoded = try quota(used: 250, limit: 500)
        #expect(QuotaPace(quota: decoded, cycleStart: nil, now: Date()) == nil)
    }

    @Test
    func `a large plan's projection is not clamped below its limit`() throws {
        let pace = try pace(used: 25000, limit: 20000)
        #expect(pace.projectedUsage >= 25000)
        #expect(pace.status == .over)
    }

    @Test
    func `a projection never falls below what has already been used`() throws {
        #expect(try pace(used: 12000, limit: 50000).projectedUsage >= 12000)
    }

    @Test
    func `an unlimited plan has no pace`() throws {
        let data = try JSONSerialization.data(withJSONObject: ["unlimited": true])
        let decoded = try CoderPadClient.decoder.decode(Quota.self, from: data)
        #expect(QuotaPace(quota: decoded, cycleStart: Date.distantPast, now: Date()) == nil)
    }

    @Test
    func `an overflowing projection saturates at the integer limit`() throws {
        #expect(try pace(used: .max, limit: .max).projectedUsage == .max)
    }

    @Test
    func `usage above a limit is an overage when the plan permits it`() throws {
        let pace = try pace(used: 501, limit: 500, overagesEnabled: true)
        #expect(pace.status == .overage)
        #expect(pace.headline == "Using overages for this cycle")
    }
}
