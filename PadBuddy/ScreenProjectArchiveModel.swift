import Foundation

struct ScreenProjectArchiveIdentity: Hashable {
    let clientIdentity: ClientTaskIdentity
    let testID: Int
    let questionID: UUID

    var filename: String {
        "ScreenProject-\(testID)-\(questionID.uuidString.lowercased()).tar.gz"
    }
}

@Observable
final class ScreenProjectArchiveModel {
    private(set) var identity: ScreenProjectArchiveIdentity?
    private(set) var downloading = false
    private(set) var error: String?
    private(set) var document: ScreenProjectArchiveDocument?
    private var generation = 0

    func reset(identity: ScreenProjectArchiveIdentity?) {
        generation += 1
        self.identity = identity
        downloading = false
        document = nil
        error = nil
    }

    func download(client: ScreenClient, identity: ScreenProjectArchiveIdentity) async {
        guard !downloading, self.identity == identity,
              identity.clientIdentity == client.taskIdentity else { return }

        let claim = generation
        downloading = true
        document = nil
        error = nil
        defer {
            if claim == generation {
                downloading = false
            }
        }
        do {
            try Task.checkCancellation()
            let testID = identity.testID
            let questionID = identity.questionID
            let bytes = try await ScreenReportOperationLimiter.shared.perform {
                try await client.projectArchive(testID: testID, questionID: questionID)
            }
            guard claim == generation, self.identity == identity, !Task.isCancelled else { return }

            try ScreenProjectArchiveDocument.validate(bytes, limit: client.maximumResponseBodyBytes)
            document = ScreenProjectArchiveDocument(data: bytes)
        } catch is CancellationError {
            return
        } catch {
            guard claim == generation, self.identity == identity, !Task.isCancelled else { return }

            self.error = String(error.localizedDescription.prefix(1000))
        }
    }

    func dismissExport() {
        document = nil
    }

    func completed(_ result: Result<URL, any Error>, identity: ScreenProjectArchiveIdentity?) {
        guard self.identity == identity else { return }

        document = nil
        if case let .failure(error) = result {
            self.error = error.localizedDescription
        }
    }
}
