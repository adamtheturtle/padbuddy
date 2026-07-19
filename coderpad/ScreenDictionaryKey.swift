//
//  ScreenDictionaryKey.swift
//  coderpad
//

import Foundation

nonisolated struct DynamicScreenCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Makes remote Screen technology/skill keys safe for rows, exports, and
/// accessibility labels. Canonical composition also makes equivalent spellings
/// collide predictably in the sorted decoder.
nonisolated func normalizedScreenDictionaryKey(_ raw: String) -> String? {
    let scrubbed = raw.unicodeScalars.map { scalar -> String in
        switch scalar.properties.generalCategory {
        case .control, .format, .privateUse, .surrogate, .unassigned:
            " "
        default:
            String(scalar)
        }
    }.joined()
    let normalized = scrubbed.precomposedStringWithCanonicalMapping
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    guard !normalized.isEmpty else { return nil }

    return String(normalized.prefix(100))
}
