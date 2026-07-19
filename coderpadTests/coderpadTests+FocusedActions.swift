//
//  coderpadTests+FocusedActions.swift
//  coderpadTests
//

@testable import CoderPad
#if os(macOS)
    import AppKit
#endif
import Testing
import UniformTypeIdentifiers

@Suite("Focused actions")
struct FocusedActionsTests {
    @Test
    func `find action identity changes with its mounted publisher`() {
        let firstPublisher = UUID()
        let baseline = FindAction(id: "pads", publisherID: firstPublisher) {}

        #expect(baseline == FindAction(id: "pads", publisherID: firstPublisher) {})
        #expect(baseline != FindAction(id: "pads", publisherID: UUID()) {})
        #expect(baseline != FindAction(id: "questions", publisherID: firstPublisher) {})
    }

    @Test
    func `print action identity changes with its mounted publisher`() {
        let firstPublisher = UUID()
        let baseline = PrintAction(id: "pad-abc", publisherID: firstPublisher, contentFingerprint: 10) {}

        #expect(baseline == PrintAction(id: "pad-abc", publisherID: firstPublisher, contentFingerprint: 10) {})
        #expect(baseline != PrintAction(id: "pad-abc", publisherID: UUID(), contentFingerprint: 10) {})
        #expect(baseline != PrintAction(id: "pad-abc", publisherID: firstPublisher, contentFingerprint: 11) {})
    }

    @Test
    func `screen invite action identity includes account and campaign payload`() {
        let firstAccount = UUID()
        let secondAccount = UUID()
        let baseline = ScreenInviteAction(id: 7, accountID: firstAccount, contentFingerprint: 10) {}

        #expect(baseline == ScreenInviteAction(id: 7, accountID: firstAccount, contentFingerprint: 10) {})
        #expect(baseline != ScreenInviteAction(id: 7, accountID: secondAccount, contentFingerprint: 10) {})
        #expect(baseline != ScreenInviteAction(id: 7, accountID: firstAccount, contentFingerprint: 11) {})
    }

    @Test
    func `screen test action identity includes its account`() {
        let firstAccount = UUID()
        let baseline = screenTestAction(accountID: firstAccount)

        #expect(baseline == screenTestAction(accountID: firstAccount))
        #expect(baseline != screenTestAction(accountID: UUID()))
    }

    @Test
    func `screen campaign action identity includes its backend`() {
        let first = ClientTaskIdentity(apiKey: "first", baseURL: URL.staticURL("https://example.com"))
        let second = ClientTaskIdentity(apiKey: "second", baseURL: URL.staticURL("https://example.com"))
        let baseline = ScreenCampaignAction(id: "campaign-7", clientIdentity: first) {} showTests: {}

        #expect(baseline == ScreenCampaignAction(id: "campaign-7", clientIdentity: first) {} showTests: {})
        #expect(baseline != ScreenCampaignAction(id: "campaign-7", clientIdentity: second) {} showTests: {})
    }

    private func screenTestAction(accountID: UUID?) -> ScreenTestAction {
        ScreenTestAction(
            id: 9,
            accountID: accountID,
            status: "waiting",
            contentFingerprint: 1,
            copySummary: {},
            openWindow: {},
            resend: {},
            cancel: {},
            delete: {}
        )
    }

    #if os(macOS)
        @Test
        func `copy-link provider publishes URL and text representations`() throws {
            let command = try #require(copyLinkCommand(hasSelection: true) { "https://example.com/pad/abc" })
            let provider = try #require(command().first)

            #expect(provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
            #expect(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
            #expect(copyLinkCommand(hasSelection: false) { "https://example.com" } == nil)
        }

        @Test
        func `multi-link pasteboard removes empty and duplicate links stably`() throws {
            let item = try #require(multiLinkPasteboardItem([
                "https://example.com/a",
                "",
                "https://example.com/b",
                "https://example.com/a"
            ]))

            #expect(item.string(forType: .URL) == "https://example.com/a")
            #expect(item.string(forType: .string) == "https://example.com/a\nhttps://example.com/b")
            #expect(multiLinkPasteboardItem(["", ""]) == nil)
        }
    #endif
}
