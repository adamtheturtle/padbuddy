import Foundation

protocol ArrayDecodingLimit {
    nonisolated static var maximumElements: Int { get }
}

nonisolated enum CacheRecordLimit: ArrayDecodingLimit {
    static let maximumElements = 20000
}

/// Read the container count before constructing model objects from a snapshot.
nonisolated struct BoundedDecodedArray<Element: Decodable, Limit: ArrayDecodingLimit>: Decodable {
    let values: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count, count > Limit.maximumElements {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Snapshot has too many records")
        }
        var decoded: [Element] = []
        while !container.isAtEnd {
            guard decoded.count < Limit.maximumElements else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Snapshot has too many records")
            }

            try decoded.append(container.decode(Element.self))
        }
        values = decoded
    }
}
