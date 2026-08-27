//
//  PadActivityMonitor.swift
//  coderpad
//

import Foundation

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()

    /// The menu bar badge and its VoiceOver label are the only consumers, and past this
    /// many updates the wording ("999 unseen pad updates") is already an approximation,
    /// so the cap costs the user nothing and keeps every formatter downstream in a range
    /// it can render (#4541).
    static let displayCap = 999

    private(set) var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        // Zero clears an obsolete activity indicator too (#1780). A negative count is a
        // miscounted delta upstream rather than anything the badge could show, so it
        // clears the indicator instead of publishing an impossible state (#4541).
        unseenChangedCount = min(max(0, changedCount), Self.displayCap)
    }
}
