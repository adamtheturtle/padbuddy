import Foundation

private nonisolated enum FavoritePadCloudLimit: ArrayDecodingLimit {
    static let maximumElements = 500
}

private nonisolated enum PadTombstoneCloudLimit: DictionaryDecodingLimit {
    static let maximumElements = 500
    static let maximumKeyBytes = 256
}

private struct CloudFavoritePad: Decodable {
    let value: FavoritePad

    init(from decoder: any Decoder) throws {
        let decoded = try FavoritePad(from: decoder)
        guard decoded.id.utf8.count <= 256, decoded.title.utf8.count <= 4096 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Favorite pad fields exceed input limits"))
        }

        value = decoded
    }
}

extension FavoritePadsStore {
    static func decodeCloudFavorites(_ data: Data) -> [String: [FavoritePad]]? {
        CloudSnapshotDecoder.decode(
            BoundedDecodedArray<CloudFavoritePad, FavoritePadCloudLimit>.self, from: data
        )?.mapValues { $0.values.map(\.value) }
    }

    static func decodeCloudTombstones(_ data: Data) -> [String: [String: Date]]? {
        CloudSnapshotDecoder.decode(
            BoundedDecodedDictionary<Date, PadTombstoneCloudLimit>.self, from: data
        )?.mapValues(\.values)
    }
}
