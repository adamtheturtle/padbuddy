//
//  CodeFileIdentity.swift
//  coderpad
//

import Foundation

enum CodeFileIdentity {
    /// The file set relevant to selection validity. Contents and response ordering
    /// do not affect it; add, remove, and rename operations do (#1885).
    static func signature(_ files: [CodeFile]) -> Set<String> {
        Set(files.lazy.map(\.id))
    }
}
