import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged pad identity bounds")
@MainActor
struct MergedPadIdentityBoundsTests {
    @Test func `invalid remote slugs never become retained merged row keys`() {
        let account = UUID()
        for invalid in [String(repeating: "x", count: 1_000_000), "bad/id", " padded ", ""] {
            #expect(MergedPadIdentity.validated(invalid) == nil)
            #expect(MergedPadsView.rowID(account: account, pad: invalid).utf8.count <= 101)
        }
        let valid = String(repeating: "x", count: 64)
        #expect(MergedPadIdentity.validated(valid) == valid)
        #expect(MergedPadsView.rowID(account: account, pad: valid) == "\(account):\(valid)")
        #expect(MergedPadsView.rowID(account: UUID(), pad: valid) != MergedPadsView.rowID(account: account, pad: valid))
    }
}
