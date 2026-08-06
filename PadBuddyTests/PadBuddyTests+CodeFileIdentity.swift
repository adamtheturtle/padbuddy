//
//  PadBuddyTests+CodeFileIdentity.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Code file identity")
struct CodeFileIdentityTests {
    @Test
    func `signature ignores ordering and contents but detects membership changes`() {
        let first = CodeFile(id: "a", path: "a.swift", contents: "one", language: "swift")
        let second = CodeFile(id: "b", path: "b.swift", contents: "two", language: "swift")
        let changed = CodeFile(id: "a", path: "a.swift", contents: "updated", language: "swift")

        #expect(CodeFileIdentity.signature([first, second]) == CodeFileIdentity.signature([second, changed]))
        #expect(CodeFileIdentity.signature([first]) != CodeFileIdentity.signature([first, second]))
    }
}
