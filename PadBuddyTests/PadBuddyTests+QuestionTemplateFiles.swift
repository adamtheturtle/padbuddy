import Foundation
@testable import PadBuddy
import Testing

@MainActor
struct QuestionTemplateFilesTests {
    @Test
    func `template defaults merge overrides additions and deletion markers`() {
        let defaults: [QuestionStarterFile] = [
            .init(path: "main.py", contents: "default"), .init(path: "remove.py", contents: "old"),
            .init(path: "blank.py", contents: ""), .init(path: "image.png", binary: true)
        ]
        let overlays: [QuestionStarterFile] = [
            .init(path: "main.py", contents: "override", hidden: true), .init(path: "remove.py", deleted: true),
            .init(path: "extra.txt", contents: "added")
        ]
        #expect(QuestionTemplateFiles.resolve(defaults: defaults, overlays: []) == defaults)
        let resolved = QuestionTemplateFiles.resolve(defaults: defaults, overlays: overlays)
        #expect(resolved.map(\.path) == ["main.py", "remove.py", "blank.py", "image.png", "extra.txt"])
        #expect(resolved[0].contents == "override")
        #expect(resolved[0].hidden == true)
        #expect(resolved[1].deleted == true)
        #expect(resolved[1].contents == nil)
        #expect(resolved[2].contents?.isEmpty == true)
        #expect(resolved[3].binary == true)
    }

    @Test(arguments: [#"{}"#, #"{"file_contents":null}"#, #"{"file_contents":[{"contents":"x"}]}"#,
                      #"{"file_contents":[{"path":"same"},{"path":"same"}]}"#])
    func `unknown or incomplete catalogue files remain unavailable`(json: String) throws {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(QuestionTemplateFiles.decode(payload) == nil)
    }

    @Test
    func `recognized catalogue files retain blank hidden binary and unavailable states`() throws {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"file_contents":[{"path":"blank.py","contents":"","hidden":false},
        {"path":"image.png","binary":true},{"path":"unknown.txt"}]}
        """#.utf8))
        let files = try #require(QuestionTemplateFiles.decode(payload))
        #expect(files[0].contents?.isEmpty == true)
        #expect(files[0].hidden == false)
        #expect(files[1].binary == true)
        #expect(files[2].contents == nil)
        #expect(QuestionTemplateFiles.decode(.object(["file_contents": .array([])]))?.isEmpty == true)
    }

    @Test
    func `reads use the selected account client and nullable template slug`() async {
        let client = CoderPadClient.mock(key: "template-read")
        let model = QuestionTemplateFilesModel()
        await model.load(client: client, template: "react") { received, slug in
            #expect(received.taskIdentity == client.taskIdentity)
            #expect(slug == "react")
            return .object(["file_contents": .array([.object(["path": .string("main.jsx"),
                                                              "contents": .string("")])])])
        }
        #expect(model.defaults?.first?.contents?.isEmpty == true)
        await model.load(client: client, template: nil) { _, _ in
            Issue.record("An absent template must not issue a request")
            return .null
        }
        #expect(model.defaults == nil)
        #expect(!model.loading)
    }

    @Test
    func `failed lookup removes previous defaults and allows retry`() async {
        let model = QuestionTemplateFilesModel()
        let client = CoderPadClient.mock(key: "template-failure")
        await model.load(client: client, template: "react") { _, _ in
            .object(["file_contents": .array([])])
        }
        #expect(model.defaults?.isEmpty == true)
        await model.load(client: client, template: "react") { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(model.defaults == nil)
        #expect(model.failed)
        #expect(!model.loading)
        await model.load(client: client, template: "react") { _, _ in .object(["file_contents": .array([])]) }
        #expect(!model.failed)
        #expect(model.defaults?.isEmpty == true)
    }

    @Test
    func `late results cannot cross account or template scopes`() async {
        let model = QuestionTemplateFilesModel()
        let first = CoderPadClient.mock(key: "template-first")
        let second = CoderPadClient.mock(key: "template-second")
        var continuation: CheckedContinuation<JSONValue, Never>?
        let task = Task {
            await model.load(client: first, template: "react") { _, _ in
                await withCheckedContinuation { continuation = $0 }
            }
        }
        while continuation == nil {
            await Task.yield()
        }
        await model.load(client: second, template: "multifile_python") { _, _ in
            .object(["file_contents": .array([])])
        }
        continuation?.resume(returning: .null)
        await task.value
        #expect(model.scope == QuestionTemplateScope(client: second.taskIdentity, template: "multifile_python"))
        #expect(model.defaults?.isEmpty == true)
    }
}
