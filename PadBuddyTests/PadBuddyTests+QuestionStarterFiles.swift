import Foundation
@testable import PadBuddy
import Testing

@Suite("Question starter-file mutations")
struct QuestionStarterFileTests {
    private struct ProviderFailure: LocalizedError {
        var errorDescription: String? {
            "Provider unavailable"
        }
    }

    @Test func `ZIP picker ignores cancellation but reports provider failures`() {
        #expect(questionZIPImportFailureMessage(CancellationError()) == nil)
        #expect(questionZIPImportFailureMessage(CocoaError(.userCancelled)) == nil)
        #expect(questionZIPImportFailureMessage(URLError(.cancelled)) == nil)
        #expect(questionZIPImportFailureMessage(ProviderFailure())
            == "Could not choose the project ZIP: Provider unavailable")
        #expect(questionZIPImportFailureMessage(QuestionZIPSelectionError.notRegularFile)
            == "Choose a regular ZIP file, not a folder or symbolic link.")
    }

    @Test func `editor insertion stops exactly at the API file boundary`() {
        var files = Array(
            repeating: QuestionStarterFileDraft(),
            count: QuestionStarterFileDraft.maximumCount - 1
        )
        files.appendStarterFileIfPossible()
        #expect(files.count == QuestionStarterFileDraft.maximumCount)
        files.appendStarterFileIfPossible()
        #expect(files.count == QuestionStarterFileDraft.maximumCount)
    }

    @Test func `create request truncates files at the API boundary`() throws {
        let files = (0 ... QuestionStarterFileDraft.maximumCount).map {
            QuestionStarterFileDraft(path: "file-\($0)", contents: "")
        }
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Project", language: "multifile_python3", description: "", instructions: "",
            solution: "", padType: "live", fileContents: files
        ))

        #expect(try #require(body.fileContents).count == QuestionStarterFileDraft.maximumCount)
    }

    @Test func `starter contents respect per-file and aggregate UTF-8 boundaries`() {
        let oversized = String(
            repeating: "🦺", count: QuestionStarterFileDraft.maximumContentBytes
        )
        let files = (0 ..< 11).map {
            QuestionStarterFileDraft(path: "file-\($0)", contents: oversized)
        }.boundedForQuestionMutation

        #expect(files.allSatisfy {
            $0.contents.utf8.count <= QuestionStarterFileDraft.maximumContentBytes
        })
        #expect(files.reduce(0) { $0 + $1.contents.utf8.count }
            == QuestionStarterFileDraft.maximumAggregateContentBytes)
        #expect(files.allSatisfy { $0.contents.utf8.count.isMultiple(of: 4) })
    }

    @Test func `validation uses the bounded path that mutations submit`() {
        let prefix = String(repeating: "a", count: NewQuestionSheet.Limits.starterFilePath - 1)
        let files = [
            QuestionStarterFileDraft(path: prefix + " x", contents: ""),
            QuestionStarterFileDraft(path: prefix + " y", contents: "")
        ]

        #expect(files.hasInvalidStarterFilePaths)
        #expect(files.boundedForQuestionMutation.map(\.requestValue.path) == [prefix, prefix])
    }

    @Test func `multi-file create preserves ordered paths empty files and Unicode`() throws {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Project", language: "multifile_python3", description: "", instructions: "",
            solution: "", padType: "live", fileContents: [
                QuestionStarterFileDraft(path: "src/世界.py", contents: "print('你好')\n"),
                QuestionStarterFileDraft(path: "tests/__init__.py", contents: "")
            ]
        ))
        let files = try #require(body.fileContents)

        #expect(files.map(\.path) == ["src/世界.py", "tests/__init__.py"])
        #expect(files.map(\.contents) == ["print('你好')\n", ""])
        #expect(body.contents == nil)
    }

    @Test func `single-file create excludes hidden project drafts`() {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Single", language: "python3", description: "", instructions: "",
            solution: "", padType: "live",
            fileContents: [QuestionStarterFileDraft(path: "main.py", contents: "print(1)")]
        ))

        #expect(body.fileContents == nil)
    }

    @Test func `SDK rejects conflicting question content sources`() {
        let body = QuestionCreate(
            title: "Conflict",
            contents: "single",
            fileContents: [QuestionFileContent(path: "main.py", contents: "project")]
        )

        #expect(throws: QuestionMutationValidationError.self) {
            _ = try JSONEncoder().encode(body)
        }
    }

    @Test func `replacement request preserves structured starter files`() throws {
        let body = QuestionUpdate(id: 42, fileContents: [
            QuestionFileContent(path: "src/é.swift", contents: "print(\"世界\")"),
            QuestionFileContent(path: "empty.txt", contents: "")
        ])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        let question = try #require(object["question"] as? [String: Any])
        let files = try #require(question["file_contents"] as? [[String: String]])

        #expect(files.map { $0["path"] } == ["src/é.swift", "empty.txt"])
        #expect(files.map { $0["contents"] } == ["print(\"世界\")", ""])
        #expect(object["contents"] == nil)
    }

    @Test func `creation drafts restore structured starter files`() throws {
        let original = QuestionCreationDraft(
            title: "Project", language: "multifile_python3", description: "", instructions: "",
            solution: "", padType: "live", draftPrompt: "", selectedSection: "instructions",
            starterFiles: [QuestionStarterFileDraft(path: "src/main.py", contents: "print('✓')")]
        )

        let restored = try JSONDecoder().decode(
            QuestionCreationDraft.self,
            from: JSONEncoder().encode(original)
        )
        #expect(restored.starterFiles == original.starterFiles)
    }

    @Test func `ZIP selections preserve Unicode filenames and zero-byte data`() {
        let selection = QuestionZIPSelection(data: Data(), filename: "proyecto-世界.zip")

        #expect(selection.upload.filename == "proyecto-世界.zip")
        #expect(selection.upload.data.isEmpty)
    }

    @Test func `ZIP selection reads a regular file`() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID().uuidString).zip")
        let contents = Data([0x50, 0x4B, 0x03, 0x04])
        try contents.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let selection = try await QuestionZIPSelection.load(from: url)

        #expect(selection.data == contents)
        #expect(selection.filename == url.lastPathComponent)
    }

    @Test func `ZIP selection rejects an oversized file before reading it`() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).zip")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(QuestionZIPSelection.maximumArchiveBytes + 1))
        try handle.close()

        await #expect(throws: QuestionZIPSelectionError.tooLarge(
            maximumBytes: QuestionZIPSelection.maximumArchiveBytes
        )) {
            _ = try await QuestionZIPSelection.load(from: url)
        }
    }

    @Test func `ZIP selection rejects non-regular items`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: QuestionZIPSelectionError.notRegularFile) {
            _ = try await QuestionZIPSelection.load(from: directory)
        }
    }

    @Test func `SDK rejects a ZIP combined with structured starter files`() async {
        let client = CoderPadClient.mock(key: "zip-conflict-\(UUID().uuidString)")
        let body = QuestionCreate(
            title: "Conflict",
            fileContents: [QuestionFileContent(path: "main.py", contents: "")]
        )

        await #expect(throws: QuestionMutationValidationError.self) {
            _ = try await client.createQuestion(
                body,
                zipFile: QuestionZIPUpload(data: Data(), filename: "empty.zip")
            )
        }
    }

    @Test func `starter paths must be present and unique without changing valid paths`() {
        #expect([QuestionStarterFileDraft(path: "src/main.py", contents: "")].hasInvalidStarterFilePaths == false)
        #expect([QuestionStarterFileDraft(path: " ", contents: "")].hasInvalidStarterFilePaths)
        #expect([
            QuestionStarterFileDraft(path: "main.py", contents: "one"),
            QuestionStarterFileDraft(path: "main.py", contents: "two")
        ].hasInvalidStarterFilePaths)
    }

    @Test func `whitespace and canonically equivalent Unicode paths collide`() throws {
        #expect([
            QuestionStarterFileDraft(path: "src/main.py", contents: "one"),
            QuestionStarterFileDraft(path: " src/main.py\n", contents: "two")
        ].hasInvalidStarterFilePaths)
        #expect([
            QuestionStarterFileDraft(path: "src/café.swift", contents: "one"),
            QuestionStarterFileDraft(path: "src/cafe\u{301}.swift", contents: "two")
        ].hasInvalidStarterFilePaths)

        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Project", language: "multifile_swift", description: "", instructions: "",
            solution: "", padType: "live", fileContents: [
                QuestionStarterFileDraft(path: " src/cafe\u{301}.swift\t", contents: "")
            ]
        ))
        #expect(try #require(body.fileContents).map(\.path) == ["src/café.swift"])
    }

    @Test(arguments: [
        "/tmp/main.py", "../secret", "src/../../x", "src\\..\\secret",
        "src//main.py", "src/./main.py", "src/control\u{0000}.py"
    ])
    func `unsafe project paths are rejected`(path: String) {
        let file = QuestionStarterFileDraft(path: path, contents: "")
        #expect(!file.hasValidCanonicalPath)
        #expect([file].hasInvalidStarterFilePaths)
    }

    @Test func `bounded normalized relative POSIX paths remain valid`() {
        let decomposed = QuestionStarterFileDraft(path: " src/cafe\u{301}.swift\n", contents: "")
        #expect(decomposed.hasValidCanonicalPath)
        #expect(decomposed.canonicalPath == "src/café.swift")
        let tooLong = QuestionStarterFileDraft(
            path: String(repeating: "a", count: NewQuestionSheet.Limits.starterFilePath + 1),
            contents: ""
        )
        #expect(!tooLong.hasValidCanonicalPath)
    }
}
