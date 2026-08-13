//
//  FavoritePadLocalRestoration.swift
//  PadBuddy
//

import Foundation

nonisolated struct FavoritePadLocalRestoreError: LocalizedError {
    let context: String
    let detail: String

    var errorDescription: String? {
        "Could not restore \(context): \(detail)"
    }
}

enum FavoritePadLocalRestoration {
    static func decode<Value: Decodable>(
        _ data: Data,
        context: String,
        using decode: (Data) throws -> Value = { try SharedCoders.decoder.decode(Value.self, from: $0) }
    ) throws -> Value {
        do {
            return try decode(data)
        } catch {
            throw FavoritePadLocalRestoreError(context: context, detail: error.localizedDescription)
        }
    }
}
