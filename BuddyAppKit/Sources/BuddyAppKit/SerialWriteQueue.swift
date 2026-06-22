//
//  SerialWriteQueue.swift
//  BuddyAppKit
//

import Foundation
import os

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk. Each enqueued unit awaits
/// the previous one, so writes apply in the order they were submitted regardless of
/// the caller's isolation.
public final class SerialWriteQueue: Sendable {
    private let tail = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    public init() {}

    public func enqueue(priority: TaskPriority = .utility, _ work: @Sendable @escaping () -> Void) {
        tail.withLock { current in
            let previous = current
            current = Task.detached(priority: priority) {
                await previous?.value
                work()
            }
        }
    }
}
