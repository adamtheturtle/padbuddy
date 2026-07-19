import BuddyAppKit
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
}

private final class Probe: Sendable {}
