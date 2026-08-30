//
//  PadEnvironmentRequestSelection.swift
//  coderpad
//

nonisolated struct PadEnvironmentRequestSelection: Sendable {
    static let limit = 100

    let ids: [Int]
    let wasTruncated: Bool

    static func select(from source: [Int]) -> Self {
        var ids: [Int] = []
        ids.reserveCapacity(min(source.count, limit))
        var seen = Set<Int>()

        for id in source where id > 0 && seen.insert(id).inserted {
            guard ids.count < limit else { return Self(ids: ids, wasTruncated: true) }

            ids.append(id)
        }
        return Self(ids: ids, wasTruncated: false)
    }
}

nonisolated struct PadEnvironmentLoadResult: Sendable {
    let loaded: [PadEnvironment]
    let failedIDs: [Int]
    let wasTruncated: Bool
}
