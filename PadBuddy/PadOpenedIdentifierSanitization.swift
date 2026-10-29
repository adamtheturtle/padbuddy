import Foundation

extension PadOpenedStore {
    static func normalizedRecordIDs(_ entries: [String: Date]) -> [String: Date] {
        var result: [String: Date] = [:]
        for (raw, timestamp) in entries {
            guard let id = normalizedRecordID(raw) else { continue }

            result[id] = max(result[id] ?? .distantPast, timestamp)
        }
        return result
    }
}
