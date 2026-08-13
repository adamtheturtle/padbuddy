//
//  DetailSelectionSettling.swift
//  PadBuddy
//

import Foundation

nonisolated enum DetailSelectionSettling {
    static func wait(
        for duration: Duration,
        using sleep: ((Duration) async throws -> Void)? = nil
    ) async throws {
        if let sleep {
            try await sleep(duration)
        } else {
            try await Task.sleep(for: duration)
        }
    }
}
