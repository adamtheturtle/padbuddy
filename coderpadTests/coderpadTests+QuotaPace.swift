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

@Suite("Quota data quality")
struct QuotaDataQualityTests {
    private func quota(_ values: [String: Any]) throws -> Quota {
        let data = try JSONSerialization.data(withJSONObject: values)
        return try CoderPadClient.decoder.decode(Quota.self, from: data)
    }

    @Test
    func `ordinary finite quota is valid`() throws {
        let value = try quota([
            "pads_used": 57, "pads_remaining": 443, "billing_cycle_pad_limit": 500,
            "quota_reset_at": "2026-08-01T00:00:00Z"
        ])
        #expect(QuotaDataQuality.problem(in: value) == nil)
    }

    @Test(arguments: [
        ["pads_used": -1],
        ["pads_remaining": -1],
        ["billing_cycle_pad_limit": 0],
        ["pads_used": 1_000_000_001]
    ])
    func `invalid numeric claims are rejected`(_ values: [String: Int]) throws {
        #expect(try QuotaDataQuality.problem(in: quota(values.mapValues { $0 as Any })) != nil)
    }

    @Test
    func `inconsistent finite totals are rejected`() throws {
        let value = try quota([
            "pads_used": 50, "pads_remaining": 100, "billing_cycle_pad_limit": 500
        ])
        #expect(QuotaDataQuality.problem(in: value) != nil)
    }

    @Test(arguments: ["1900-01-01T00:00:00Z", "2200-01-01T00:00:00Z"])
    func `implausible reset dates are rejected`(_ reset: String) throws {
        #expect(try QuotaDataQuality.problem(in: quota(["quota_reset_at": reset])) != nil)
    }
}
