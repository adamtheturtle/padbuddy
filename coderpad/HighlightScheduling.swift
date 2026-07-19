//
//  HighlightScheduling.swift
//  coderpad
//

import Foundation

enum HighlightScheduling {
    static let debounce = Duration.milliseconds(120)

    static func waitForSettledInput() async -> Bool {
        do {
            try await Task.sleep(for: debounce)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
