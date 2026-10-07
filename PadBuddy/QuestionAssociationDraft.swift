import Foundation

struct QuestionAssociationDraft: Codable, Equatable {
    var shared: Bool?
    var databaseID = ""

    var parsedDatabaseID: Int? {
        Int(databaseID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var validationMessage: String? {
        guard !databaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let identifier = parsedDatabaseID, (1 ... Int(Int32.max)).contains(identifier) else {
            return String(localized:
                "Enter a database ID from 1 to 2147483647, or leave it empty to keep the association.")
        }

        return nil
    }

    var isMeaningful: Bool {
        shared != nil || !databaseID.isEmpty
    }

    func update(questionID: Int) -> QuestionUpdate {
        QuestionUpdate(id: questionID, shared: shared, customDatabaseID: parsedDatabaseID)
    }

    func applying(to body: QuestionCreate) -> QuestionCreate {
        var body = body
        body.shared = shared
        body.customDatabaseID = parsedDatabaseID
        return body
    }
}

@Observable
final class QuestionAssociationModel {
    private(set) var saving = false
    private(set) var error: String?

    func save(_ draft: QuestionAssociationDraft, questionID: Int, client: CoderPadClient,
              isCurrent: () -> Bool) async -> Question? {
        guard !saving, draft.isMeaningful, draft.validationMessage == nil else { return nil }

        saving = true
        error = nil
        defer { saving = false }
        do {
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            let question = try await client.updateQuestion(draft.update(questionID: questionID))
            try Task.checkCancellation()
            guard isCurrent() else { throw BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed }

            return question
        } catch is CancellationError {
            return nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
