import Foundation

private nonisolated enum PadOpenedCloudLimit: DictionaryDecodingLimit {
    static let maximumElements = 500
    static let maximumKeyBytes = 256
}

extension PadOpenedStore {
    /// Apply input budgets and canonical identifiers before any cross-device union.
    static func decodeCloudHistory(_ data: Data) -> [String: [String: Date]]? {
        CloudSnapshotDecoder.decode(
            BoundedDecodedDictionary<Date, PadOpenedCloudLimit>.self, from: data
        )?.mapValues { normalizedRecordIDs($0.values) }
    }
}
