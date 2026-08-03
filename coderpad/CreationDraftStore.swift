//
//  CreationDraftStore.swift
//  coderpad
//

import Foundation

struct PadCreationDraft: Codable, Equatable {
    var title: String
    var language: String
    var ownerEmail: String
    var isPrivate: Bool
    var executionEnabled: Bool
    var questionID: Int?
    var teamID: String?

    var isMeaningful: Bool {
        !title.isEmpty || language != "python3" || !ownerEmail.isEmpty || isPrivate
            || !executionEnabled || questionID != nil || teamID != nil
    }
}

struct QuestionCreationDraft: Codable, Equatable {
    var title: String
    var language: String
    var description: String
    var instructions: String
    var solution: String
    var padType: String
    var draftPrompt: String
    var selectedSection: String
    var starterFiles: [QuestionStarterFileDraft]?

    var isMeaningful: Bool {
        !title.isEmpty || language != "python3" || !description.isEmpty || !instructions.isEmpty
            || !solution.isEmpty || padType != QuestionPadType.fallback || !draftPrompt.isEmpty
            || starterFiles?.isEmpty == false
    }
}

enum CreationDraftStore {
    private static let prefix = "creationDraft.v1"

    static func load<Value: Decodable>(_ type: Value.Type, kind: String, account: UUID) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key(kind: kind, account: account)) else { return nil }

        return try? SharedCoders.decoder.decode(type, from: data)
    }

    static func save(_ value: some Encodable, kind: String, account: UUID) {
        guard let data = try? SharedCoders.encoder.encode(value) else { return }

        UserDefaults.standard.set(data, forKey: key(kind: kind, account: account))
    }

    static func clear(kind: String, account: UUID) {
        UserDefaults.standard.removeObject(forKey: key(kind: kind, account: account))
    }

    private static func key(kind: String, account: UUID) -> String {
        "\(prefix).\(kind).\(account.uuidString)"
    }
}
