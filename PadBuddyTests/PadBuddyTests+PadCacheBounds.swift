import Foundation
@testable import PadBuddy
import Testing

private nonisolated enum TinyArrayLimit: ArrayDecodingLimit {
    static let maximumElements = 2
}

@Suite("Pad cache snapshot bounds")
@MainActor
struct PadCacheBoundsTests {
    @Test func `array record limits are enforced before accepting the decoded collection`() throws {
        let accepted = try JSONDecoder().decode(
            BoundedDecodedArray<Int, TinyArrayLimit>.self, from: Data("[1,2]".utf8)
        )
        #expect(accepted.values == [1, 2])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BoundedDecodedArray<Int, TinyArrayLimit>.self, from: Data("[1,2,3]".utf8))
        }
    }

    @Test func `cache publication bounds record counts and rejects oversized identities`() {
        let invalid = Pad(id: String(repeating: "x", count: 1_000_000), title: "Invalid")
        let valid = Pad(id: "valid", title: "Valid")
        #expect(PadsCacheStore.normalizedDiskPads([invalid, valid]) == [valid])
        let rows = (0 ... CacheRecordLimit.maximumElements).map { Pad(id: "pad\($0)", title: "Pad") }
        let retained = PadsCacheStore.normalizedDiskPads(rows)
        #expect(retained.count == CacheRecordLimit.maximumElements)
        #expect(retained.last?.id == "pad\(CacheRecordLimit.maximumElements - 1)")
    }
}
