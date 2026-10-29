import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen report request ownership")
struct ScreenReportRequestTests {
    @Test func `rapid report actions share one synchronous claim`() throws {
        var request = ScreenReportRequest()
        let first = try #require(request.claim())
        #expect(request.isActive)
        #expect(request.claim() == nil)
        request.finish(first)
        #expect(!request.isActive)
        #expect(request.claim() != nil)
    }

    @Test func `old completion cannot retire replacement session work`() throws {
        var request = ScreenReportRequest()
        let old = try #require(request.claim())
        request.cancel()
        let replacement = try #require(request.claim())
        #expect(!request.isCurrent(old))
        request.finish(old)
        #expect(request.isCurrent(replacement))
        #expect(request.isActive)
    }
}
