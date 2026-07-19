//
//  ScreenAPI+Metrics.swift
//  coderpad
//

import Foundation

nonisolated enum ScreenReportMetric {
    static func percentage<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Double? {
        guard let value = try container.decodeIfPresent(Double.self, forKey: key) else { return nil }
        guard value.isFinite, (0 ... 100).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Screen percentage must be between 0 and 100."
            )
        }

        return value
    }
}
