import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen report request ownership")
struct ScreenReportRequestTests {
    @Test func `rapid report actions share one synchronous claim`() throws {
        var request = ScreenReportRequest()
        let firstClaim = request.claim()
        let first = try #require(firstClaim)
        #expect(request.isActive)
        let duplicate = request.claim()
        #expect(duplicate == nil)
        request.finish(first)
        #expect(!request.isActive)
        let next = request.claim()
        #expect(next != nil)
    }

    @Test func `old completion cannot retire replacement session work`() throws {
        var request = ScreenReportRequest()
        let oldClaim = request.claim()
        let old = try #require(oldClaim)
        request.cancel()
        let replacementClaim = request.claim()
        let replacement = try #require(replacementClaim)
        #expect(!request.isCurrent(old))
        request.finish(old)
        #expect(request.isCurrent(replacement))
        #expect(request.isActive)
    }
}
