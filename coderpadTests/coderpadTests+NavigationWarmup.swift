//
//  coderpadTests+NavigationWarmup.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

/// Records what a warm body observed. A `@MainActor` class so the `@Sendable`
/// warm closure can mutate it.
@MainActor
final class WarmProbe {
    var finished = false
    var cancelled = false
}

@Suite("Navigation warmup")
struct NavigationWarmupTests {
    @Test
    @MainActor
    func `a warm that overruns its budget is cancelled`() async {
        let probe = WarmProbe()

        await NavigationSessionLoader.withWarmBudget(.milliseconds(10)) {
            do {
                try await Task.sleep(for: .seconds(60))
                probe.finished = true
            } catch {
                probe.cancelled = true
            }
        }

        #expect(probe.cancelled)
        #expect(!probe.finished)
    }

    @Test
    @MainActor
    func `a warm that finishes inside its budget runs to completion`() async {
        let probe = WarmProbe()

        await NavigationSessionLoader.withWarmBudget(.seconds(60)) {
            probe.finished = true
        }

        #expect(probe.finished)
        #expect(!probe.cancelled)
    }
}
