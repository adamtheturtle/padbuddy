//
//  PadBuddyTests+LiveFilterPersistence.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Live filter persistence debounce")
@MainActor
struct LiveFilterPersistenceTests {
    private func key() -> String {
        "test.liveFilter.\(UUID().uuidString)"
    }

    /// The point of the debounce: a burst of keystrokes must produce one write, not
    /// one per character (#4783).
    @Test func `a burst of changes collapses to the last write`() async throws {
        let key = key()
        let recorded = Recorder()

        for index in 0 ..< 10 {
            LiveFilterPersistence.shared.schedule(key: key) { recorded.append(index) }
        }
        try await Task.sleep(for: LiveFilterPersistence.interval + .milliseconds(300))

        #expect(recorded.values == [9])
    }

    /// Leaving the pane must not lose the filters it was showing.
    @Test func `flush writes the pending snapshot immediately`() {
        let key = key()
        let recorded = Recorder()

        LiveFilterPersistence.shared.schedule(key: key) { recorded.append(1) }
        LiveFilterPersistence.shared.flush(key: key)

        #expect(recorded.values == [1])
    }

    @Test func `a flushed snapshot is not written again by its timer`() async throws {
        let key = key()
        let recorded = Recorder()

        LiveFilterPersistence.shared.schedule(key: key) { recorded.append(1) }
        LiveFilterPersistence.shared.flush(key: key)
        try await Task.sleep(for: LiveFilterPersistence.interval + .milliseconds(300))

        #expect(recorded.values == [1])
    }

    @Test func `flushing an unknown key does nothing`() {
        LiveFilterPersistence.shared.flush(key: key())
    }

    /// Two panes queue independently; flushing one must not drop the other.
    @Test func `keys are independent`() {
        let first = key()
        let second = key()
        let recorded = Recorder()

        LiveFilterPersistence.shared.schedule(key: first) { recorded.append(1) }
        LiveFilterPersistence.shared.schedule(key: second) { recorded.append(2) }
        LiveFilterPersistence.shared.flush(key: first)

        #expect(recorded.values == [1])

        LiveFilterPersistence.shared.flush(key: second)

        #expect(recorded.values == [1, 2])
    }

    @MainActor
    private final class Recorder {
        private(set) var values: [Int] = []

        func append(_ value: Int) {
            values.append(value)
        }
    }
}
