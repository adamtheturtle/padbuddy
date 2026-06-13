//
//  CoderPadAPI.swift
//  coderpad
//

import Foundation
import os.log

nonisolated let apiLogger = Logger(subsystem: "com.coderpad.app", category: "api")

extension KeyedDecodingContainer {
    /// Like `try? decodeIfPresent`, but logs the underlying error so silent API drift
    /// shows up in Console rather than producing an empty UI with no diagnostic.
    nonisolated func loggedDecodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            apiLogger.debug(
                """
                decodeIfPresent '\(key.stringValue, privacy: .public)' \
                as \(String(describing: type), privacy: .public) \
                failed: \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
    }
}

// MARK: - Models

nonisolated struct Pad: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let state: String
    let ownerEmail: String
    let language: String?
    let participants: [String]
    let url: String
    let playback: String?
    /// API URL for this pad's event log. Convenience field; `padEvents(padID:)`
    /// derives the same URL from `id`, so this is decoded only for fidelity.
    let events: String?
    /// Private interviewer notes. Round-trips with `PadCreate`/`PadUpdate`.
    let notes: String?
    /// URL of the pad's whiteboard drawing image, if any.
    let drawing: String?
    /// Pad code contents (legacy single-file representation).
    let contents: String?
    /// Firebase history URL for the pad.
    let history: String?
    let createdAt: Date?
    let updatedAt: Date?
    let endedAt: Date?
    let type: String?
    let executionEnabled: Bool?
    let isPrivate: Bool?
    let activeEnvironmentID: Int?
    let padEnvironmentIDs: [Int]
    let questionIDs: [Int]
    let team: PadTeam?

    enum CodingKeys: String, CodingKey {
        case id, title, state, language, participants, url, playback, type, team
        case notes, drawing, contents, history, events
        case ownerEmail = "owner_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case endedAt = "ended_at"
        case executionEnabled = "execution_enabled"
        case isPrivate = "private"
        case activeEnvironmentID = "active_environment_id"
        case padEnvironmentIDs = "pad_environment_ids"
        case questionIDs = "question_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = container.loggedDecodeIfPresent(String.self, forKey: .title) ?? ""
        state = container.loggedDecodeIfPresent(String.self, forKey: .state) ?? "unknown"
        ownerEmail = container.loggedDecodeIfPresent(String.self, forKey: .ownerEmail) ?? ""
        language = container.loggedDecodeIfPresent(String.self, forKey: .language)
        // The live API can include `null` entries in `participants` (e.g. an
        // anonymous or not-yet-named guest), so decode as optional strings and
        // drop the nulls rather than letting one null fail the whole array.
        participants = (container.loggedDecodeIfPresent([String?].self, forKey: .participants) ?? [])
            .compactMap(\.self)
        url = container.loggedDecodeIfPresent(String.self, forKey: .url) ?? ""
        playback = container.loggedDecodeIfPresent(String.self, forKey: .playback)
        events = container.loggedDecodeIfPresent(String.self, forKey: .events)
        notes = container.loggedDecodeIfPresent(String.self, forKey: .notes)
        drawing = container.loggedDecodeIfPresent(String.self, forKey: .drawing)
        contents = container.loggedDecodeIfPresent(String.self, forKey: .contents)
        history = container.loggedDecodeIfPresent(String.self, forKey: .history)
        createdAt = container.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = container.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
        endedAt = container.loggedDecodeIfPresent(Date.self, forKey: .endedAt)
        type = container.loggedDecodeIfPresent(String.self, forKey: .type)
        executionEnabled = container.loggedDecodeIfPresent(Bool.self, forKey: .executionEnabled)
        isPrivate = container.loggedDecodeIfPresent(Bool.self, forKey: .isPrivate)
        activeEnvironmentID = container.loggedDecodeIfPresent(Int.self, forKey: .activeEnvironmentID)
        padEnvironmentIDs = container.loggedDecodeIfPresent([Int].self, forKey: .padEnvironmentIDs) ?? []
        questionIDs = container.loggedDecodeIfPresent([Int].self, forKey: .questionIDs) ?? []
        team = container.loggedDecodeIfPresent(PadTeam.self, forKey: .team)
    }
}

extension Pad {
    /// The `updatedAt` timestamp, but only when it carries information beyond the
    /// pad's end time. Ending a pad is itself a write, so for ended pads
    /// `updated_at` usually equals `ended_at` and surfacing both is redundant.
    /// Show it only when a later edit (notes, feedback) moved `updated_at`
    /// meaningfully past the end.
    var informativeUpdatedAt: Date? {
        guard let updatedAt else { return nil }
        guard let endedAt else { return updatedAt }
        return updatedAt.timeIntervalSince(endedAt) > 60 ? updatedAt : nil
    }
}

nonisolated struct PadTeam: Codable, Hashable {
    let id: String
    let name: String
}

nonisolated struct PadEvent: Decodable, Identifiable, Hashable {
    var id: String {
        "\(createdAt?.timeIntervalSince1970 ?? 0)-\(kind)-\(userName ?? "")-\(message)"
    }

    let message: String
    let kind: String
    /// Event-specific context: the language run for `ran`, the question ID for
    /// `added_question`, "spectator" for a spectator `joined`, etc.
    let metadata: String?
    let userName: String?
    let userEmail: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case message, kind, metadata
        case userName = "user_name"
        case userEmail = "user_email"
        case createdAt = "created_at"
    }
}

/// One file within a pad environment. Single-file languages return one of these;
/// multi-file frameworks/projects return one per file in the project.
nonisolated struct PadEnvironmentFile: Decodable, Hashable {
    let path: String?
    let contents: String?
    let history: String?
}

nonisolated struct PadEnvironment: Decodable, Identifiable, Hashable {
    let id: Int
    let padID: Int?
    let questionID: Int?
    /// e.g. "examples/035-django-shopping-list" when seeded from a CoderPad example.
    let exampleQuestionID: String?
    let language: String?
    let fileContents: [PadEnvironmentFile]
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, language
        case padID = "pad_id"
        case questionID = "question_id"
        case exampleQuestionID = "example_question_id"
        case fileContents = "file_contents"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        padID = container.loggedDecodeIfPresent(Int.self, forKey: .padID)
        questionID = container.loggedDecodeIfPresent(Int.self, forKey: .questionID)
        exampleQuestionID = container.loggedDecodeIfPresent(String.self, forKey: .exampleQuestionID)
        language = container.loggedDecodeIfPresent(String.self, forKey: .language)
        fileContents = container.loggedDecodeIfPresent([PadEnvironmentFile].self, forKey: .fileContents) ?? []
        createdAt = container.loggedDecodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = container.loggedDecodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// The combined code across all files in the environment, for a simple preview.
    /// Multi-file projects are concatenated with a header per file path.
    var contents: String? {
        let files = fileContents.compactMap { file -> String? in
            guard let body = file.contents, !body.isEmpty else { return nil }
            if fileContents.count > 1, let path = file.path, !path.isEmpty {
                return "// \(path)\n\(body)"
            }
            return body
        }
        return files.isEmpty ? nil : files.joined(separator: "\n\n")
    }
}
