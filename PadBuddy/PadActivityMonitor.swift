//
//  PadActivityMonitor.swift
//  coderpad
//

import Foundation

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        // Zero clears an obsolete activity indicator too (#1780).
        unseenChangedCount = changedCount
    }
}
