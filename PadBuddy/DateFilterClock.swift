//
//  DateFilterClock.swift
//  PadBuddy
//

import Foundation

nonisolated enum DateFilterClock {
    static func wait(using sleep: (() async throws -> Void)? = nil) async throws {
        if let sleep {
            try await sleep()
        } else {
            try await Task.sleep(for: .seconds(60))
        }
    }
}
