//
//  ScreenClient+Pagination.swift
//  coderpad
//

extension ScreenClient {
    /// Every test session matching the filters, following offset pagination to the
    /// end. Convenience over `listTests` for callers that want the full list.
    nonisolated func listAllTests(campaignID: Int? = nil,
                                  product: String? = nil,
                                  candidateEmail: String? = nil,
                                  from: Int? = nil,
                                  until: Int? = nil) async throws -> [ScreenTestSession] {
        try await listAllTestsResult(campaignID: campaignID, product: product,
                                     candidateEmail: candidateEmail, from: from, until: until).tests
    }

    nonisolated func listAllTestsResult(campaignID: Int? = nil,
                                        product: String? = nil,
                                        candidateEmail: String? = nil,
                                        from: Int? = nil,
                                        until: Int? = nil) async throws -> ScreenTestListResult {
        var all: [ScreenTestSession] = []
        var discardedCount = 0
        var seenIDs: Set<Int> = []
        var seenStarts: Set<Int> = []
        var start: Int?
        var pageCount = 0
        var snapshotTotal: Int?
        while true {
            guard pageCount < Self.maximumFullListPages else {
                throw CoderPadError.decode("Screen pagination exceeded the maximum page count.")
            }

            pageCount += 1
            let page = try await listTests(campaignID: campaignID, product: product,
                                           candidateEmail: candidateEmail, from: from,
                                           until: until, start: start)
            let additions = page.tests.filter { seenIDs.insert($0.id).inserted }
            guard additions.count == page.tests.count else {
                throw CoderPadError.decode("Screen pagination repeated a session while loading pages.")
            }

            discardedCount += page.discardedTestCount
            if pageCount == 1 {
                snapshotTotal = page.pagination?.total
            } else if page.pagination?.total != snapshotTotal {
                throw CoderPadError.decode("Screen pagination total changed while loading pages.")
            }
            guard additions.count <= Self.maximumFullListItems - all.count else {
                throw CoderPadError.decode("Screen pagination exceeded the maximum item count.")
            }

            all.append(contentsOf: additions)
            guard let pagination = page.pagination, pagination.hasMoreItems else {
                if let snapshotTotal, all.count + discardedCount != snapshotTotal {
                    throw CoderPadError.decode("Screen pagination changed before every session was loaded.")
                }
                break
            }

            let currentStart = start ?? -1
            guard let next = pagination.nextStart, next > currentStart,
                  seenStarts.insert(next).inserted else {
                throw CoderPadError.decode("Screen pagination returned an invalid next offset.")
            }

            start = next
        }
        return ScreenTestListResult(tests: all, discardedCount: discardedCount)
    }
}
