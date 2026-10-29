import Foundation

/// Retains one newest copy per ID with at most 1,000 sessions of working storage.
enum ScreenTestRetention {
    static let maximumSessions = 1000

    static func newest(_ sessions: [ScreenTestSession]) -> (sessions: [ScreenTestSession], omitted: Int) {
        var retained = Selection()
        for session in sessions {
            retained.insert(session)
        }
        // Keep the API's order for small responses, as before. No eviction can
        // occur in this branch, so the heap's ordinal map contains every ID.
        let result = sessions.count <= maximumSessions
            ? retained.inServerOrder()
            : retained.heap.sorted(by: isNewer)
        return (result, sessions.count - result.count)
    }

    private static func isNewer(_ lhs: ScreenTestSession, than rhs: ScreenTestSession) -> Bool {
        let lhsTime = lhs.lastActivityTime ?? Int.min
        let rhsTime = rhs.lastActivityTime ?? Int.min
        return lhsTime == rhsTime ? lhs.id > rhs.id : lhsTime > rhsTime
    }

    /// A worst-first heap and an index only for retained IDs. An evicted ID needs
    /// no tombstone: an older copy still cannot beat the improving cutoff.
    private struct Selection {
        var heap: [ScreenTestSession] = []
        var positions: [Int: Int] = [:]
        var ordinals: [Int: Int] = [:]

        mutating func insert(_ session: ScreenTestSession) {
            if let index = positions[session.id] {
                guard isNewer(session, than: heap[index]) else { return }

                heap[index] = session
                siftDown(index)
            } else if heap.count < maximumSessions {
                ordinals[session.id] = heap.count
                positions[session.id] = heap.count
                heap.append(session)
                siftUp(heap.count - 1)
            } else if let oldest = heap.first, isNewer(session, than: oldest) {
                positions.removeValue(forKey: oldest.id)
                ordinals.removeValue(forKey: oldest.id)
                heap[0] = session
                positions[session.id] = 0
                siftDown(0)
            }
        }

        func inServerOrder() -> [ScreenTestSession] {
            heap.sorted { (ordinals[$0.id] ?? 0) < (ordinals[$1.id] ?? 0) }
        }

        mutating func swap(_ lhs: Int, _ rhs: Int) {
            heap.swapAt(lhs, rhs)
            positions[heap[lhs].id] = lhs
            positions[heap[rhs].id] = rhs
        }

        mutating func siftUp(_ start: Int) {
            var index = start
            while index > 0 {
                let parent = (index - 1) / 2
                guard isNewer(heap[parent], than: heap[index]) else { break }

                swap(parent, index)
                index = parent
            }
        }

        mutating func siftDown(_ start: Int) {
            var index = start
            while index * 2 + 1 < heap.count {
                var child = index * 2 + 1
                if child + 1 < heap.count, isNewer(heap[child], than: heap[child + 1]) {
                    child += 1
                }
                guard isNewer(heap[index], than: heap[child]) else { break }

                swap(index, child)
                index = child
            }
        }
    }
}
