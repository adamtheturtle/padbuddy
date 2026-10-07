import Foundation

@Observable
final class ScreenQuestionAuthoringModel {
    var draft = ScreenQuestionSave(type: .text)
    private(set) var loading = false
    private(set) var saving = false
    private(set) var uploading = false
    private(set) var error: String?
    private(set) var savedID: UUID?
    private(set) var uploadFilename: String?
    private(set) var contextChangedAfterSave = false
    private(set) var identity: ScreenBankIdentity?
    private(set) var editingID: UUID?
    private(set) var ready = false
    private var generation = 0
    private var uploadIdentity: ScreenBankIdentity?

    func prepare(questionID: UUID?, client: ScreenClient, identity: ScreenBankIdentity) async {
        guard identity.clientIdentity == client.taskIdentity else { return }

        generation += 1
        let claim = generation
        self.identity = identity
        editingID = questionID
        draft = ScreenQuestionSave(type: .text)
        savedID = nil
        uploadIdentity = nil
        uploadFilename = nil
        ready = false
        loading = true
        error = nil
        defer {
            if generation == claim {
                loading = false
            }
        }
        do {
            try Task.checkCancellation()
            if let questionID {
                let question = try await client.getQuestion(id: questionID)
                guard question.id == questionID else {
                    throw CoderPadError.decode(String(localized: "The service returned a different question."))
                }

                let hydrated = try ScreenQuestionHydration.editable(question)
                guard generation == claim, !Task.isCancelled else { return }

                draft = hydrated
            }
            ready = !Task.isCancelled && generation == claim
        } catch is CancellationError {
            return
        } catch {
            guard generation == claim, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }

    func changeType(_ type: ScreenQuestionSave.QuestionType) {
        guard editingID == nil, !saving, !uploading, draft.type != type else { return }

        draft.type = type
        draft.codeDetails = nil
        draft.mcqDetails = nil
        draft.textDetails = nil
        draft.videoDetails = nil
        draft.projectDetails = nil
        draft.evaluation = nil
        uploadIdentity = nil
        uploadFilename = nil
    }

    func upload(_ data: Data, filename: String, client: ScreenClient, isCurrent: () -> Bool) async {
        guard ready, !saving, !uploading, savedID == nil, editingID == nil, draft.type == .project,
              let identity, identity.clientIdentity == client.taskIdentity else { return }

        uploading = true
        error = nil
        let claim = generation
        defer { uploading = false }
        do {
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            try ScreenProjectArchiveInput.validate(data)
            let reference = try await client.uploadTemporaryFile(data)
            guard generation == claim, self.identity == identity, isCurrent(), !Task.isCancelled else { return }
            guard !reference.id.isEmpty, reference.id.utf8.count <= 1024 else {
                throw CoderPadError
                    .decode(String(localized: "The upload returned an invalid temporary file reference."))
            }

            var project = draft.projectDetails ?? ScreenProjectInput()
            project.temporaryFileID = reference.id
            draft.projectDetails = project
            uploadIdentity = identity
            uploadFilename = filename
        } catch is CancellationError {
            return
        } catch {
            guard generation == claim, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }

    func reportFileError(_ error: any Error) {
        self.error = error.localizedDescription
    }

    func save(client: ScreenClient, isCurrent: () -> Bool) async -> UUID? {
        guard ready, !saving, !uploading, savedID == nil, let identity,
              identity.clientIdentity == client.taskIdentity else { return nil }

        saving = true
        error = nil
        let claim = generation
        defer { saving = false }
        do {
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            try ScreenQuestionSubmission.validate(draft)
            if draft.projectDetails?.temporaryFileID != nil {
                guard editingID == nil, uploadIdentity == identity else {
                    throw CoderPadError
                        .decode(String(localized: "Upload the project archive in this account before saving."))
                }
            }
            let result: ScreenQuestionDetails
            if let editingID {
                result = try await client.updateQuestion(id: editingID, draft)
                guard result.id == editingID else {
                    throw CoderPadError.decode(String(localized: "The service returned a different question."))
                }
            } else {
                result = try await client.createQuestion(draft).question
            }
            // Record success before checking the current account. A second POST would duplicate the question.
            guard generation == claim else { return nil }

            savedID = result.id
            contextChangedAfterSave = !isCurrent() || Task.isCancelled
            return contextChangedAfterSave ? nil : result.id
        } catch is CancellationError {
            return nil
        } catch {
            guard generation == claim, !Task.isCancelled else { return nil }

            self.error = error.localizedDescription
            return nil
        }
    }
}

enum ScreenQuestionSubmission {
    static func validate(_ draft: ScreenQuestionSave) throws {
        let bytes = try JSONEncoder().encode(draft)
        guard bytes.count <= 1024 * 1024 else {
            throw CoderPadError.decode(String(localized: "Question content is too large to submit."))
        }

        let value = try JSONDecoder().decode(JSONValue.self, from: bytes)
        try validateNumbers(value, depth: 0)
        if let indexes = draft.evaluation?.choiceSelection?.correctChoiceIndexes,
           let choices = draft.mcqDetails?.choices {
            guard Set(indexes).count == indexes.count, indexes.allSatisfy({ choices.indices.contains($0) }) else {
                throw CoderPadError
                    .decode(String(localized: "Correct choices must refer to unique existing choice indexes."))
            }
        }
    }

    private static func validateNumbers(_ value: JSONValue, depth: Int) throws {
        guard depth <= 32 else {
            throw CoderPadError.decode(String(localized: "Question content is nested too deeply."))
        }

        switch value {
        case let .object(fields):
            for (key, child) in fields where key != "function_signature" {
                try validateNumbers(child, depth: depth + 1)
            }

        case let .array(items):
            guard items.count <= 200 else {
                throw CoderPadError.decode(String(localized: "Use no more than 200 items per question field."))
            }

            for child in items {
                try validateNumbers(child, depth: depth + 1)
            }

        case let .number(number):
            guard number >= 0, number <= Decimal(Int32.max) else {
                throw CoderPadError.decode(String(localized: "Question numbers must be from 0 to 2147483647."))
            }

        default: break
        }
    }
}
