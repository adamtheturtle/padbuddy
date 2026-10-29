import Foundation
import os

/// Corrupt mirrors are explicitly invalidated; valid unrelated account values survive cleanup.
enum CloudAccountRemoval {
    case unchanged
    case updated(Data)
    case invalidated(Data, String)
    case failed(String)

    static func prepare<Value: Codable>(
        data: Data, syncID: String,
        decode: (Data) throws -> [String: Value] = {
            try SharedCoders.decoder.decode([String: Value].self, from: $0)
        },
        encode: ([String: Value]) throws -> Data = { try SharedCoders.encoder.encode($0) }
    ) -> Self {
        transforming(data: data, empty: [:], decode: decode,
                     remove: { $0.removeValue(forKey: syncID) != nil }, encode: encode)
    }

    static func transforming<Value: Codable>(
        data: Data, empty: Value, decode: (Data) throws -> Value,
        remove: (inout Value) -> Bool,
        encode: (Value) throws -> Data = { try SharedCoders.encoder.encode($0) }
    ) -> Self {
        var value: Value
        do {
            value = try decode(data)
        } catch {
            do {
                let message = "Invalidated malformed account cloud data: \(error.localizedDescription)"
                return try .invalidated(encode(empty), message)
            } catch {
                return .failed("Could not invalidate malformed account cloud data: \(error.localizedDescription)")
            }
        }
        guard remove(&value) else { return .unchanged }

        do {
            return try .updated(encode(value))
        } catch {
            return .failed("Could not encode cleaned account cloud data: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func apply(key: String) -> Bool {
        switch self {
        case .unchanged:
            return false

        case let .updated(data):
            CloudSyncStore.shared.mirror(data, forKey: key)
            return true

        case let .invalidated(data, message):
            persistenceLogger.error("\(message, privacy: .private); key: \(key, privacy: .public)")
            CloudSyncStore.shared.mirror(data, forKey: key)
            return true

        case let .failed(message):
            persistenceLogger.error("\(message, privacy: .private); key: \(key, privacy: .public)")
            return false
        }
    }
}
