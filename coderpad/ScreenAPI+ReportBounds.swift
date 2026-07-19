//
//  ScreenAPI+ReportBounds.swift
//  coderpad
//

import Foundation

nonisolated struct BoundedScreenWarnings: Decodable {
    private static let maximumEntries = 100
    private static let maximumLength = 500
    let values: [String]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [String] = []
        decoded.reserveCapacity(min(container.count ?? 0, Self.maximumEntries))
        while !container.isAtEnd, decoded.count < Self.maximumEntries {
            let raw = try container.decode(String.self)

            let normalized = raw.components(separatedBy: .controlCharacters)
                .joined(separator: " ")
                .split(whereSeparator: \Character.isWhitespace)
                .joined(separator: " ")
            guard !normalized.isEmpty else { continue }

            decoded.append(String(normalized.prefix(Self.maximumLength)))
        }
        values = decoded
    }
}
