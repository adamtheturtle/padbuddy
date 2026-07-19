import BuddyAppKit
import Dispatch
import os
import Testing

@Suite("Serial write queue")
struct SerialWriteQueueTests {
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
}

private final class Probe: Sendable {}
