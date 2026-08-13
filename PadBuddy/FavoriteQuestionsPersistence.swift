//
//  FavoriteQuestionsPersistence.swift
//  PadBuddy
//

import Foundation
import os

extension FavoriteQuestionsStore {
    private static let persistenceLogger = Logger(
        subsystem: "com.coderpad.app",
        category: "favorite-questions"
    )

    static func decodePersisted<Value: Decodable>(
        _ type: Value.Type,
        key: String,
        defaults: UserDefaults = .standard
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try SharedCoders.decoder.decode(type, from: data)
        } catch {
            persistenceLogger.error(
                "Discarding corrupt favorite-question data for \(key, privacy: .public): \(error)"
            )
            defaults.removeObject(forKey: key)
            return nil
        }
    }
}
