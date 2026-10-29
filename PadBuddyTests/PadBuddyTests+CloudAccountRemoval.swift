import Foundation
@testable import PadBuddy
import Testing

@Suite("Cloud account removal")
struct CloudAccountRemovalTests {
    private struct Failure: Error {}

    @Test func `valid unrelated account data survives removal`() throws {
        let data = try JSONEncoder().encode(["removed": [1], "kept": [2]])
        let result = CloudAccountRemoval.prepare(data: data, syncID: "removed", decode: {
            try JSONDecoder().decode([String: [Int]].self, from: $0)
        })
        guard case let .updated(updated) = result else { Issue.record("Expected cleanup"); return }

        #expect(try JSONDecoder().decode([String: [Int]].self, from: updated) == ["kept": [2]])
    }

    @Test func `unencodable cleanup is reported without replacing valid data`() throws {
        let data = try JSONEncoder().encode(["removed": [1]])
        let result = CloudAccountRemoval.prepare(data: data, syncID: "removed", decode: {
            try JSONDecoder().decode([String: [Int]].self, from: $0)
        }, encode: { _ in throw Failure() })
        guard case .failed = result else { Issue.record("Expected explicit failure"); return }
    }

    @Test func `a corrupt merged collection is explicitly replaced with an empty collection`() throws {
        let result = CloudAccountRemoval.transforming(data: Data("invalid".utf8), empty: [Int](), decode: {
            try JSONDecoder().decode([Int].self, from: $0)
        }, remove: { _ in true })
        guard case let .invalidated(data, _) = result else { Issue.record("Expected invalidation"); return }

        #expect(try JSONDecoder().decode([Int].self, from: data).isEmpty)
    }
}
