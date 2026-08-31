//
//  PadBuddyTests+AppStateRestorationReset.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Restored app state reset", .serialized)
struct AppStateRestorationResetTests {
    @Test func `sidebar layout is restored state`() {
        #expect(AppStateRestorationReset.includes(key: "sidebar.collapsed"))
    }

    @Test func `unrelated preferences are not restored state`() {
        #expect(!AppStateRestorationReset.includes(key: "general.appearance"))
        #expect(!AppStateRestorationReset.includes(key: "accounts"))
    }

    @Test @MainActor func `reset notifies every live scene`() {
        let counter = Counter()
        let observer = NotificationCenter.default.addObserver(
            forName: .appStateRestorationDidReset,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { counter.value += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = AppStateRestorationReset.reset()

        #expect(counter.value == 1)
    }

    @MainActor
    private final class Counter {
        var value = 0
    }
}
