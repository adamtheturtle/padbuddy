//
//  ScreenAPI+Identity.swift
//  coderpad
//

import Foundation

nonisolated func validatedScreenID(
    _ id: Int,
    codingPath: [any CodingKey],
    kind: String
) throws -> Int {
    guard id > 0 else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath,
            debugDescription: "Screen \(kind) ID must be positive."
        ))
    }

    return id
}
