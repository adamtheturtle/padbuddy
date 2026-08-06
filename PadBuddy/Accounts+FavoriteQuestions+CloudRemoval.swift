import Foundation

extension FavoriteQuestionsStore {
    func removeFromCloud(syncID: String) {
        guard CloudSyncStore.shared.isAvailable else { return }

        removeCloudAccount(syncID, key: Self.cloudKey, value: [FavoriteQuestion].self)
        removeCloudAccount(syncID, key: Self.cloudTombstonesKey, value: [String: Date].self)
    }

    private func removeCloudAccount<Value: Codable>(_ syncID: String, key: String, value _: Value.Type) {
        guard let data = CloudSyncStore.shared.data(forKey: key),
              let cloud = try? SharedCoders.decoder.decode([String: Value].self, from: data),
              let updatedCloud = CloudSyncMerge.removingAccount(syncID, from: cloud),
              let updated = try? SharedCoders.encoder.encode(updatedCloud)
        else { return }

        CloudSyncStore.shared.mirror(updated, forKey: key)
    }
}
