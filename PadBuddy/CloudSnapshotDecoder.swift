import Foundation

private nonisolated enum CloudAccountKeysLimit: DictionaryDecodingLimit {
    static let maximumElements = 256
    static let maximumKeyBytes = 4096
}

enum CloudSnapshotDecoder {
    nonisolated static let maximumBytes = 1_048_576

    static func decode<Value: Decodable>(_: Value.Type, from data: Data) -> [String: Value]? {
        guard data.count <= maximumBytes else { return nil }

        return try? SharedCoders.decoder.decode(
            BoundedDecodedDictionary<Value, CloudAccountKeysLimit>.self, from: data
        ).values
    }
}
