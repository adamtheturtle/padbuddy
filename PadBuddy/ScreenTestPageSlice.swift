import Foundation

nonisolated struct ScreenTestPageSlice {
    static let pageSize = 50
    let sessions: [ScreenTestSession]
    let nextStart: Int?
    let discardedCount: Int

    init(page: ScreenTestsPage, requestedStart: Int) throws {
        guard page.tests.count <= Self.pageSize,
              page.discardedTestCount <= Self.pageSize - page.tests.count else {
            throw CoderPadError.decode(String(localized:
                "The server returned too many test sessions. Try a narrower date range.", table: "ScreenPaging"))
        }

        if page.pagination?.hasMoreItems == true {
            guard let next = page.pagination?.nextStart, next > requestedStart else {
                throw CoderPadError.decode(String(localized:
                    "The next page is unavailable. Reload the test sessions.", table: "ScreenPaging"))
            }

            nextStart = next
        } else {
            nextStart = nil
        }
        sessions = page.tests
        discardedCount = page.discardedTestCount
    }
}
