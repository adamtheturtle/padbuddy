//
//  CreationDraftStore.swift
//  coderpad
//

import Foundation
import os

struct PadCreationDraft: Codable, Equatable {
    var title: String
    var language: String
    var ownerEmail: String
    var isPrivate: Bool
    var executionEnabled: Bool
    var questionID: Int?
    var teamID: String?
    var access: PadAccessDraft?

    var isMeaningful: Bool {
        !title.isEmpty || language != "python3" || !ownerEmail.isEmpty || isPrivate
            || !executionEnabled || questionID != nil || teamID != nil || access?.isMeaningful == true
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
    var instructionName: String?
    var association: QuestionAssociationDraft?

    /// The section the user was last editing is part of the draft, so moving to one and
    /// leaving is a change worth restoring; without it the sheet reopened on Instructions
    /// and silently discarded where they were (#4547).
    static let defaultSection = QuestionDraftSection.instructions.rawValue

    var isMeaningful: Bool {
        !title.isEmpty || language != "python3" || !description.isEmpty || !instructions.isEmpty
            || !solution.isEmpty || padType != QuestionPadType.fallback || !draftPrompt.isEmpty
            || starterFiles?.isEmpty == false || selectedSection != Self.defaultSection
            || instructionName?.isEmpty == false
            || association?.isMeaningful == true
    }
}

enum CreationDraftLoad<Value> {
    case missing
    case value(Value)
    case corrupt
}

enum CreationDraftStore {
    private static let prefix = "creationDraft.v1"
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "creation-drafts")

    static func load<Value: Decodable>(
        _ type: Value.Type, kind: String, account: UUID, defaults: UserDefaults = .standard
    ) -> CreationDraftLoad<Value> {
        let storageKey = key(kind: kind, account: account)
        guard let data = defaults.data(forKey: storageKey) else { return .missing }

        do {
            return try .value(SharedCoders.decoder.decode(type, from: data))
        } catch {
            defaults.removeObject(forKey: storageKey)
            logger.error("""
            Discarded corrupt \(kind, privacy: .public) creation draft for account \
            \(account.uuidString, privacy: .private): \(error.localizedDescription, privacy: .public)
            """)
            return .corrupt
        }
    }

    static func save(
        _ value: some Encodable, kind: String, account: UUID, defaults: UserDefaults = .standard
    ) {
        guard let data = try? SharedCoders.encoder.encode(value) else { return }

        defaults.set(data, forKey: key(kind: kind, account: account))
    }

    static func clear(kind: String, account: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(kind: kind, account: account))
    }

    private static func key(kind: String, account: UUID) -> String {
        "\(prefix).\(kind).\(account.uuidString)"
    }
}
