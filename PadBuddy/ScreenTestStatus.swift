//
//  ScreenTestStatus.swift
//  coderpad
//

import Foundation

nonisolated enum ScreenTestStatusPolicy {
    static func isWaiting(_ status: String?) -> Bool {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "waiting"
    }
}
