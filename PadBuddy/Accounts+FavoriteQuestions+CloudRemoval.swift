import Foundation
import os

enum FavoriteQuestionCloudRemoval {
    case unchanged
    case updated(Data)
    case failed(String)

    static func prepare<Value: Codable>(
        data: Data,
        syncID: String,
        decode: (Data) throws -> [String: Value] = {
            try SharedCoders.decoder.decode([String: Value].self, from: $0)
        },
        encode: ([String: Value]) throws -> Data = { try SharedCoders.encoder.encode($0) }
    ) -> Self {
        let cloud: [String: Value]
        do {
            cloud = try decode(data)
        } catch {
            return .failed("Could not decode favorite-question cloud data: \(error.localizedDescription)")
        }
        guard let updatedCloud = CloudSyncMerge.removingAccount(syncID, from: cloud) else {
            return .unchanged
        }
        do {
            return .updated(try encode(updatedCloud))
        } catch {
            return .failed("Could not encode cleaned favorite-question cloud data: \(error.localizedDescription)")
        }
    }
}

extension FavoriteQuestionsStore {
    func removeFromCloud(syncID: String) {
        guard CloudSyncStore.shared.isAvailable else { return }

        removeCloudAccount(syncID, key: Self.cloudKey, value: [FavoriteQuestion].self)
        removeCloudAccount(syncID, key: Self.cloudTombstonesKey, value: [String: Date].self)
    }

    private func removeCloudAccount<Value: Codable>(_ syncID: String, key: String, value _: Value.Type) {
        guard let data = CloudSyncStore.shared.data(forKey: key) else { return }

        let outcome = FavoriteQuestionCloudRemoval.prepare(
            data: data,
            syncID: syncID,
            decode: { try SharedCoders.decoder.decode([String: Value].self, from: $0) }
        )
        switch outcome {
        case .unchanged:
            return
        case let .updated(updated):
            CloudSyncStore.shared.mirror(updated, forKey: key)
        case let .failed(message):
            persistenceLogger.error("\(message, privacy: .public); key: \(key, privacy: .public)")
        }
    }
}
