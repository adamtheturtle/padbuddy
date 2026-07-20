import BuddyAppKit
import Dispatch
import Foundation
import os
import Testing

@Suite("Serial write queue")
struct SerialWriteQueueTests {
    private enum TestFailure: Error, Equatable {
        case writeFailed
    }

    @Test
    func `writes run in submission order`() async {
        let queue = SerialWriteQueue()
        let values = OSAllocatedUnfairLock<[Int]>(initialState: [])
        for value in 0 ..< 100 {
            queue.enqueue { values.withLock { $0.append(value) } }
        }

        await queue.waitUntilIdle()

        #expect(values.withLock { $0 } == Array(0 ..< 100))
    }

    @Test
    func `caller priorities do not change worker priority`() async {
        let queue = SerialWriteQueue()
        let priorities = OSAllocatedUnfairLock<[QualityOfService]>(initialState: [])
        for priority: TaskPriority in [.background, .high, .low, .userInitiated] {
            queue.enqueue(priority: priority) {
                priorities.withLock { $0.append(Thread.current.qualityOfService) }
            }
        }

        await queue.waitUntilIdle()

        #expect(priorities.withLock { $0 } == Array(repeating: .utility, count: 4))
    }

    @Test
    func `completed work is released when the queue becomes idle`() async {
        let queue = SerialWriteQueue()
        weak var retained: Probe?
        do {
            let probe = Probe()
            retained = probe
            queue.enqueue { _ = probe }
        }

        await queue.waitUntilIdle()

        #expect(retained == nil)
    }

    @Test
    func `pending writes with the same key coalesce to the newest`() async {
        let queue = SerialWriteQueue()
        let release = DispatchSemaphore(value: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        let values = OSAllocatedUnfairLock<[Int]>(initialState: [])
        queue.enqueue {
            started.withLock { $0 = true }
            release.wait()
            values.withLock { $0.append(0) }
        }
        while !started.withLock({ $0 }) {
            await Task.yield()
        }
        for value in 1 ... 100 {
            queue.enqueue(coalescingKey: "snapshot") { values.withLock { $0.append(value) } }
        }
        release.signal()
        await queue.waitUntilIdle()

        #expect(values.withLock { $0 } == [0, 100])
        #expect(queue.metrics.coalescedCount == 99)
        #expect(queue.metrics.droppedCount == 0)
    }

    @Test
    func `unkeyed backlog is bounded and reports dropped work`() async {
        let queue = SerialWriteQueue(maximumPendingJobs: 3)
        let release = DispatchSemaphore(value: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        let values = OSAllocatedUnfairLock<[Int]>(initialState: [])
        queue.enqueue {
            started.withLock { $0 = true }
            release.wait()
            values.withLock { $0.append(0) }
        }
        while !started.withLock({ $0 }) {
            await Task.yield()
        }
        for value in 1 ... 5 {
            queue.enqueue { values.withLock { $0.append(value) } }
        }
        release.signal()
        await queue.waitUntilIdle()

        #expect(values.withLock { $0 } == [0, 3, 4, 5])
        #expect(queue.metrics.droppedCount == 2)
    }

    @Test
    func `awaitable writes surface execution errors`() async {
        let queue = SerialWriteQueue()

        await #expect(throws: TestFailure.writeFailed) {
            try await queue.enqueueAndWait { throw TestFailure.writeFailed }
        }
    }

    @Test
    func `awaitable writes support async work`() async throws {
        let queue = SerialWriteQueue()
        let values = OSAllocatedUnfairLock<[Int]>(initialState: [])
        try await queue.enqueueAndWait {
            await Task.yield()
            values.withLock { $0.append(1) }
        }

        #expect(values.withLock { $0 } == [1])
    }

    @Test
    func `coalesced awaitable work reports admission loss`() async throws {
        let queue = SerialWriteQueue()
        let release = DispatchSemaphore(value: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        queue.enqueue {
            started.withLock { $0 = true }
            release.wait()
        }
        while !started.withLock({ $0 }) {
            await Task.yield()
        }

        let superseded = Task { try await queue.enqueueAndWait(coalescingKey: "snapshot") {} }
        while queue.metrics.pendingCount == 0 {
            await Task.yield()
        }
        let current = Task { try await queue.enqueueAndWait(coalescingKey: "snapshot") {} }
        await #expect(throws: SerialWriteQueueError.coalesced) { try await superseded.value }
        release.signal()
        try await current.value
    }
}

private final class Probe: Sendable {}
