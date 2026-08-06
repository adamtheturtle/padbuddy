//
//  PadBuddyTests+NavigationWarmup.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Focused router requests")
@MainActor
struct RouterWindowFocusTests {
    @Test func `a window is unfocused until its environment is sampled`() {
        #expect(!RouterWindowFocus().isFocused)
    }

    @Test func `an inactive request is claimed once by the next focused window`() {
        var state = FocusedWindowRequestState()
        state.request(.commandPalette)

        let inactiveClaim = state.claim(.commandPalette, isFocused: false)
        let focusedClaim = state.claim(.commandPalette, isFocused: true)
        let duplicateClaim = state.claim(.commandPalette, isFocused: true)
        #expect(!inactiveClaim)
        #expect(focusedClaim)
        #expect(!duplicateClaim)
    }

    @Test func `bursts while inactive coalesce into one presentation`() {
        var state = FocusedWindowRequestState()
        state.request(.reload)
        state.request(.reload)

        let firstClaim = state.claim(.reload, isFocused: true)
        let secondClaim = state.claim(.reload, isFocused: true)
        #expect(firstClaim)
        #expect(!secondClaim)
    }
}

@Suite("Navigation prefetch health")
@MainActor
struct NavigationPrefetchHealthTests {
    @Test func `failures are scoped by endpoint kind and clear after success`() {
        let account = UUID()
        NavigationPrefetchHealth.record(URLError(.timedOut), account: account, kind: .pads)
        #expect(NavigationPrefetchHealth.snapshot(kind: .pads)[account] != nil)
        #expect(NavigationPrefetchHealth.snapshot(kind: .questions)[account] == nil)
        NavigationPrefetchHealth.clear(account: account, kind: .pads)
        #expect(NavigationPrefetchHealth.snapshot(kind: .pads)[account] == nil)
    }
}

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
