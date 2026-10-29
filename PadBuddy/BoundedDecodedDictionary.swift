import Foundation

protocol DictionaryDecodingLimit: ArrayDecodingLimit {
    nonisolated static var maximumKeyBytes: Int { get }
}

private nonisolated struct SnapshotKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

nonisolated struct BoundedDecodedDictionary<Value: Decodable, Limit: DictionaryDecodingLimit>: Decodable {
    let values: [String: Value]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SnapshotKey.self)
        let keys = container.allKeys
        guard keys.count <= Limit.maximumElements,
              keys.allSatisfy({ $0.stringValue.utf8.count <= Limit.maximumKeyBytes }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Snapshot dictionary exceeds its limits"))
        }

        var decoded: [String: Value] = [:]
        for key in keys {
            decoded[key.stringValue] = try container.decode(Value.self, forKey: key)
        }
        values = decoded
    }
}
