import Foundation
@testable import PadBuddy
import SwiftUI
import Testing

@Suite("Screen candidate project archives")
struct ScreenProjectArchiveTests {
    @Test @MainActor
    func `native downloads retain original gzip bytes and use UUID scoped export filenames`() async throws {
        let client = ScreenClient.mock(key: "archive-export-" + UUID().uuidString)
        let id = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let identity = ScreenProjectArchiveIdentity(
            clientIdentity: client.taskIdentity,
            testID: 5001,
            questionID: id
        )
        let model = ScreenProjectArchiveModel()
        model.reset(identity: identity)
        await model.download(client: client, identity: identity)
        let document = try #require(model.document)
        #expect(try await document.data == (client.projectArchive(testID: 5001, questionID: id)))
        #expect(document.data.prefix(3) == Data([0x1F, 0x8B, 0x08]))
        #expect(identity.filename == "ScreenProject-5001-4143ca74-2f0e-4151-90d6-e1428739450b.tar.gz")
        #expect(model.error == nil)
        #expect(model.downloading == false)
        model.dismissExport()
        #expect(model.document == nil)
    }

    @Test @MainActor
    func `unavailable projects missing UUIDs and permission failures never stage an export`() async throws {
        let client = ScreenClient.mock(key: "archive-errors-" + UUID().uuidString)
        let id = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let model = ScreenProjectArchiveModel()
        for (testID, questionID) in [(5003, id), (5001, UUID())] {
            let identity = ScreenProjectArchiveIdentity(
                clientIdentity: client.taskIdentity,
                testID: testID,
                questionID: questionID
            )
            model.reset(identity: identity)
            await model.download(client: client, identity: identity)
            #expect(model.document == nil)
            #expect(model.error != nil)
        }
        let denied = ScreenClient.mock(unauthorized: true)
        let identity = ScreenProjectArchiveIdentity(
            clientIdentity: denied.taskIdentity,
            testID: 5001,
            questionID: id
        )
        model.reset(identity: identity)
        await model.download(client: denied, identity: identity)
        #expect(model.document == nil)
        #expect(model.error != nil)
    }

    @Test @MainActor
    func `selection and client changes discard archives and old exporter completion cannot change a new selection`(
    ) async throws {
        let client = ScreenClient.mock(key: "archive-scope-" + UUID().uuidString)
        let id = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let old = ScreenProjectArchiveIdentity(clientIdentity: client.taskIdentity, testID: 5001, questionID: id)
        let model = ScreenProjectArchiveModel()
        model.reset(identity: old)
        await model.download(client: client, identity: old)
        #expect(model.document != nil)
        let other = ScreenClient.mock(key: "archive-other-" + UUID().uuidString)
        let new = ScreenProjectArchiveIdentity(clientIdentity: other.taskIdentity, testID: 5001, questionID: id)
        model.reset(identity: new)
        #expect(model.document == nil)
        await model.download(client: client, identity: new)
        #expect(model.document == nil)
        await model.download(client: other, identity: new)
        #expect(model.document != nil)
        model.completed(.failure(CocoaError(.fileWriteNoPermission)), identity: old)
        #expect(model.document != nil)
        #expect(model.error == nil)
        model.completed(.failure(CocoaError(.fileWriteNoPermission)), identity: new)
        #expect(model.document == nil)
        #expect(model.error != nil)
        model.reset(identity: nil)
        #expect(model.error == nil)
    }

    @Test @MainActor
    func `cancelled archive downloads do not stage bytes or report an ordinary failure`() async throws {
        let client = ScreenClient.mock(key: "archive-cancel-" + UUID().uuidString)
        let id = try #require(UUID(uuidString: "4143ca74-2f0e-4151-90d6-e1428739450b"))
        let identity = ScreenProjectArchiveIdentity(
            clientIdentity: client.taskIdentity,
            testID: 5001,
            questionID: id
        )
        let model = ScreenProjectArchiveModel()
        model.reset(identity: identity)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.download(client: client, identity: identity)
        }
        await cancelled.value
        #expect(model.document == nil)
        #expect(model.error == nil)
        #expect(model.downloading == false)
    }

    @Test
    func `export validation rejects HTML empty bodies unsupported gzip and configured size violations`() throws {
        for data in [Data(), Data("<html>not an archive</html>".utf8), Data([0x1F, 0x8B, 0x00])] {
            #expect(throws: (any Error).self) { try ScreenProjectArchiveDocument.validate(data, limit: 100) }
        }
        let bytes = Data([0x1F, 0x8B, 0x08, 0])
        try ScreenProjectArchiveDocument.validate(bytes, limit: bytes.count)
        #expect(throws: (any Error).self) {
            try ScreenProjectArchiveDocument.validate(bytes, limit: bytes.count - 1)
        }
    }

    @Test @MainActor
    func `archive controls render for project results and sessions without UUID project entries`() async throws {
        let client = ScreenClient.mock(key: "archive-render-" + UUID().uuidString)
        let session = try await client.getTest(id: 5001)
        #expect(ImageRenderer(content: ScreenProjectArchivesSection(client: client, session: session)
                .frame(width: 600))
            .cgImage != nil)
        let empty = try ScreenTestSession(id: 5001, status: "waiting")
        #expect(ImageRenderer(content: ScreenProjectArchivesSection(client: client, session: empty)
                .frame(width: 600))
            .cgImage != nil)
    }
}
