//
//  PadBuddyTests+QuestionContentSaveChain.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Question content save chain cancellation (#4596)")
@MainActor
struct QuestionContentSaveChainTests {
    private final class Runs {
        var didRun = false
        var count = 0
    }

    @Test func `a cancelled caller does not run its queued save`() async {
        let runs = Runs()
        let key = "question-\(UUID().uuidString)"
        let gate = PermitGate()
        // Occupy the chain so the second save has to queue behind it.
        let holder = Task {
            await QuestionContentSaveChain.run(key: key) {
                await gate.wait()
                return true
            }
        }
        // Let the holder claim the chain before queueing behind it.
        await Task.yield()
        let queued = Task {
            await QuestionContentSaveChain.run(key: key) {
                runs.didRun = true
                return true
            }
        }
        await Task.yield()

        queued.cancel()
        await gate.open()
        _ = await holder.value

        #expect(await queued.value == false)
        #expect(!runs.didRun)
    }

    @Test func `an uncancelled save still runs`() async {
        let runs = Runs()
        let key = "question-\(UUID().uuidString)"

        let result = await QuestionContentSaveChain.run(key: key) {
            runs.count += 1
            return true
        }

        #expect(result)
        #expect(runs.count == 1)
    }
}
