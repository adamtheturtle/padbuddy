import Foundation
import os

typealias FavoriteQuestionCloudRemoval = CloudAccountRemoval

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
        outcome.apply(key: key)
    }
}
