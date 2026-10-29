import Foundation
@testable import PadBuddy
import Testing

private nonisolated enum GrowingListFixture {
    static func snapshots(terminated: AsyncStream<Bool>.Continuation) -> AsyncThrowingStream<[Int], any Error> {
        AsyncThrowingStream { continuation in
            let work = Task.detached {
                do {
                    for count in 1 ... 100 {
                        try Task.checkCancellation()
                        continuation.yield(Array(0 ..< count))
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                work.cancel()
                terminated.yield(true)
                terminated.finish()
            }
        }
    }
}

@Suite("Retained list windows")
nonisolated struct RetainedListStreamTests {
    @Test(.timeLimit(.minutes(1)))
    @concurrent func `reaching a window stops upstream work and caps the final snapshot`() async throws {
        let termination = AsyncStream<Bool>.makeStream()
        var counts: [Int] = []
        for try await snapshot in RetainedListStream.bounded(
            GrowingListFixture.snapshots(terminated: termination.continuation), limit: 5
        ) {
            counts.append(snapshot.count)
        }
        #expect(counts.last == 5)
        #expect(counts.allSatisfy { $0 <= 5 })
        #expect(await termination.stream.first(where: \.self) == true)
    }

    @Test func `a single oversized page is truncated for complete list readers`() async throws {
        let source = AsyncThrowingStream<[Int], any Error> {
            $0.yield(Array(0 ... RetainedListStream.maximumRecords))
            $0.finish()
        }
        let result = try await RetainedListStream.collect(source)
        #expect(result.count == RetainedListStream.maximumRecords)
        #expect(result.first == 0)
        #expect(result.last == RetainedListStream.maximumRecords - 1)
    }

    @Test func `empty and failed streams retain their meanings`() async throws {
        enum Failure: Error { case unavailable }
        let empty = AsyncThrowingStream<[Int], any Error> { $0.yield([]); $0.finish() }
        #expect(try await RetainedListStream.collect(empty).isEmpty)
        let failed = AsyncThrowingStream<[Int], any Error> { $0.finish(throwing: Failure.unavailable) }
        await #expect(throws: Failure.self) { try await RetainedListStream.collect(failed) }
    }

    @Test func `a capped window cannot prove an absent record was deleted`() {
        #expect(RetainedListStream.isComplete(RetainedListStream.maximumRecords - 1))
        #expect(!RetainedListStream.isComplete(RetainedListStream.maximumRecords))
        #expect(!RetainedListStream.isComplete(RetainedListStream.maximumRecords + 1))
    }
}
