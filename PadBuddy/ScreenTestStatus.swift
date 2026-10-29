//
//  ScreenTestStatus.swift
//  coderpad
//

import Foundation

nonisolated enum ScreenTestStatusPolicy {
    static let maximumKeyScalars = 64

    static func normalized(_ status: String) -> String {
        let bounded = String(status.unicodeScalars.prefix(maximumKeyScalars).map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: Character(scalar)
            }
        })
        let key = bounded.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return String(key.unicodeScalars.prefix(maximumKeyScalars))
    }

    static func isWaiting(_ status: String?) -> Bool {
        status.map(normalized) == "waiting"
    }
}
