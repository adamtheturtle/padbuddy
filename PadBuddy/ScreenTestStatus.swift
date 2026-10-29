//
//  ScreenTestStatus.swift
//  coderpad
//

import Foundation

nonisolated enum ScreenTestStatusPolicy {
    static func normalized(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isWaiting(_ status: String?) -> Bool {
        status.map(normalized) == "waiting"
    }
}
