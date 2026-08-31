//
//  PadBuddyTests+IPadQuickActions.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("iPad quick actions")
struct IPadQuickActionTests {
    @Test
    func `shortcuts delivered before activation are all kept, in order`() {
        var queue = IPadQuickActionQueue()

        let acceptedPads = queue.enqueue(type: IPadQuickAction.showPads.rawValue)
        let acceptedQuestion = queue.enqueue(type: IPadQuickAction.newQuestion.rawValue)
        let beforeActivation = queue.drain()
        #expect(acceptedPads)
        #expect(acceptedQuestion)
        #expect(beforeActivation.isEmpty)

        queue.activate()
        let actions = queue.drain()
        #expect(actions == [.showPads, .newQuestion])
    }

    @Test
    func `a drained queue does not repeat its actions`() {
        var queue = IPadQuickActionQueue()

        _ = queue.enqueue(type: IPadQuickAction.newPad.rawValue)
        queue.activate()

        let firstDrain = queue.drain()
        let secondDrain = queue.drain()
        #expect(firstDrain == [.newPad])
        #expect(secondDrain.isEmpty)
    }

    @Test
    func `an unknown shortcut is rejected rather than queued`() {
        var queue = IPadQuickActionQueue()

        let accepted = queue.enqueue(type: "com.example.unknown")
        #expect(!accepted)
        queue.activate()

        let actions = queue.drain()
        #expect(actions.isEmpty)
    }

    @Test
    func `shortcuts arriving after activation run immediately`() {
        var queue = IPadQuickActionQueue()
        queue.activate()

        let accepted = queue.enqueue(type: IPadQuickAction.showQuestions.rawValue)
        let actions = queue.drain()
        #expect(accepted)
        #expect(actions == [.showQuestions])
    }

    @Test
    func `shortcuts arriving after deactivation wait for the next activation`() {
        var queue = IPadQuickActionQueue()
        queue.activate()
        queue.deactivate()

        let accepted = queue.enqueue(type: IPadQuickAction.showPads.rawValue)
        let whileInactive = queue.drain()
        queue.activate()
        let afterReactivation = queue.drain()

        #expect(accepted)
        #expect(whileInactive.isEmpty)
        #expect(afterReactivation == [.showPads])
    }

    @Test
    func `creation shortcuts require creation availability`() {
        #expect(!IPadQuickAction.newPad.isAvailable(canCreate: false))
        #expect(!IPadQuickAction.newQuestion.isAvailable(canCreate: false))
        #expect(IPadQuickAction.newPad.isAvailable(canCreate: true))
        #expect(IPadQuickAction.newQuestion.isAvailable(canCreate: true))
    }

    @Test
    func `list shortcuts remain available without creation access`() {
        #expect(IPadQuickAction.showPads.isAvailable(canCreate: false))
        #expect(IPadQuickAction.showQuestions.isAvailable(canCreate: false))
    }
}
