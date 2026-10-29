import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen candidate presentation")
struct ScreenCandidatePresentationTests {
    @Test func `identity labels bound and sanitize names and emails`() throws {
        let session = try ScreenTestSession(
            id: 1, candidateName: "Ada\n\u{202E}" + String(repeating: "a", count: 10000),
            candidateEmail: "ada\t@example.com" + String(repeating: "x", count: 10000)
        )
        #expect(session.screenCandidateName.unicodeScalars.count <= 128)
        #expect(session.screenCandidateEmail.unicodeScalars.count <= 254)
        #expect(!session.screenCandidateDisplay.contains("\u{202E}"))
        #expect(!session.screenCandidateEmail.contains("\t"))
        #expect(session.screenCandidateDisplay == session.screenCandidateName)
    }

    @Test func `empty sanitized names fall back to email without duplicating clipboard columns`() throws {
        let session = try ScreenTestSession(id: 1, candidateName: " \n\u{202E}",
                                            candidateEmail: "ada@example.com")
        #expect(session.screenCandidateDisplay == "ada@example.com")
        let fields = session.screenCopyText.split(separator: "\t", omittingEmptySubsequences: false)
        #expect(fields[1].isEmpty)
        #expect(fields[2] == "ada@example.com")
        #expect(session.screenCopyText.components(separatedBy: "ada@example.com").count == 2)
    }

    @Test func `missing identities use the shared unknown candidate fallback`() throws {
        let session = try ScreenTestSession(id: 1)
        #expect(session.screenCandidateDisplay == String(localized: "Unknown candidate"))
    }

    @Test func `action diagnostics retain only bounded safe context`() {
        let failure = ScreenActionFailure(operation: String(repeating: "x", count: 10000), testID: 1,
                                          candidate: "Ada\u{202E}" + String(repeating: "a", count: 10000),
                                          accountName: String(repeating: "b", count: 10000),
                                          reason: "Error\n" + String(repeating: "c", count: 10000))
        #expect(failure.operation.unicodeScalars.count <= 80)
        #expect(failure.candidate.unicodeScalars.count <= 254)
        #expect(failure.accountName?.unicodeScalars.count ?? 0 <= 128)
        #expect(failure.reason.unicodeScalars.count <= 1024)
        #expect(!failure.detail.contains("\u{202E}"))
    }
}
