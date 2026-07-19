//
//  coderpadTests+IPadQuickActions.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("iPad quick actions")
struct IPadQuickActionTests {
    @Test
    func `shortcuts delivered before activation are all kept, in order`() {
        var queue = IPadQuickActionQueue()

        #expect(queue.enqueue(type: IPadQuickAction.showPads.rawValue))
        #expect(queue.enqueue(type: IPadQuickAction.newQuestion.rawValue))
        #expect(queue.drain().isEmpty)

        queue.activate()
        #expect(queue.drain() == [.showPads, .newQuestion])
    }

    @Test
    func `a drained queue does not repeat its actions`() {
        var queue = IPadQuickActionQueue()

        _ = queue.enqueue(type: IPadQuickAction.newPad.rawValue)
        queue.activate()

        #expect(queue.drain() == [.newPad])
        #expect(queue.drain().isEmpty)
    }

    @Test
    func `an unknown shortcut is rejected rather than queued`() {
        var queue = IPadQuickActionQueue()

        #expect(queue.enqueue(type: "com.example.unknown") == false)
        queue.activate()

        #expect(queue.drain().isEmpty)
    }

    @Test
    func `shortcuts arriving after activation run immediately`() {
        var queue = IPadQuickActionQueue()
        queue.activate()

        #expect(queue.enqueue(type: IPadQuickAction.showQuestions.rawValue))
        #expect(queue.drain() == [.showQuestions])
    }
}
