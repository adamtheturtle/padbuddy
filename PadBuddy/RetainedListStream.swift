import Foundation

nonisolated enum RetainedListStream {
    static let maximumRecords = CacheRecordLimit.maximumElements

    /// A full window may have more records beyond it; absence is not proof of deletion.
    static func isComplete(_ count: Int) -> Bool {
        count < maximumRecords
    }

    static func bounded<Item: Sendable>(
        _ source: AsyncThrowingStream<[Item], any Error>, limit: Int = maximumRecords
    ) -> AsyncThrowingStream<[Item], any Error> {
        guard limit > 0 else { return AsyncThrowingStream { $0.finish() } }

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let work = Task.detached {
                do {
                    for try await snapshot in source {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.count <= limit ? snapshot : Array(snapshot.prefix(limit)))
                        if snapshot.count >= limit {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    static func collect<Item: Sendable>(_ source: AsyncThrowingStream<[Item], any Error>) async throws -> [Item] {
        var latest: [Item] = []
        for try await snapshot in bounded(source) {
            latest = snapshot
        }
        try Task.checkCancellation()
        return latest
    }

    static func subtitle(_ visible: String, retainedCount: Int) -> String {
        guard !isComplete(retainedCount) else { return visible }

        return String(localized: "\(visible) · showing up to \(maximumRecords) most recent", table: "RetainedLists")
    }
}
