//
//  coderpadTests+ScreenTimeFilters.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen test date windows")
struct ScreenTestDateWindowTests {
    private let reference = Date(timeIntervalSince1970: 2_000_000_000)

    @Test(arguments: [
        (ScreenTestDateRange.last7, 7),
        (ScreenTestDateRange.last30, 30),
        (ScreenTestDateRange.last90, 90)
    ])
    func `recent ranges use one stable bounded window`(range: ScreenTestDateRange, days: Int) throws {
        let bounds = range.bounds(relativeTo: reference)
        let expectedUntil = 2_000_000_000_000
        let expectedFrom = expectedUntil - days * 24 * 60 * 60 * 1000

        #expect(bounds.from == expectedFrom)
        #expect(bounds.until == expectedUntil)
        #expect(try #require(bounds.from) <= #require(bounds.until))
    }

    @Test
    func `all time remains unbounded`() {
        let bounds = ScreenTestDateRange.all.bounds(relativeTo: reference)
        #expect(bounds.from == nil)
        #expect(bounds.until == nil)
    }

    @Test
    func `invalid ranges are rejected before transport`() async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        let invalidRanges: [(from: Int?, until: Int?)] = [(-1, nil), (nil, -1), (2, 1)]

        for range in invalidRanges {
            do {
                _ = try await client.listTests(from: range.from, until: range.until)
                Issue.record("Expected an invalid Screen time filter to throw")
            } catch let error as CoderPadError {
                #expect(error.description.contains("time filter"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
