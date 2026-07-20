//
//  DesignSystemRenderTests.swift
//  coderpadTests
//
//  Render ("snapshot") coverage for the app-coupled design-system primitives.
//  Rather than pixel-comparing against committed reference images — which are
//  fragile across OS/font-rendering changes and need recording/maintenance —
//  these use SwiftUI's built-in `ImageRenderer` to confirm each primitive
//  rasterizes to a valid, non-zero image. That guards against the common
//  regressions (a primitive that crashes when rendered, or collapses to zero
//  size) with no third-party dependency and nothing to keep in sync.
//
//  The generic primitives (Card, DetailSection, SectionHeader, LabeledRow,
//  StatTile, Chip, MetaLabel, the label/tint/symbol AvatarCircle) now live in the
//  CoderPadDesignSystem package and are covered by its own RenderTests (#377).
//  This file keeps the app-coupled cases: StateBadge (on PadState), the
//  AvatarCircle(account:) convenience, the account/appearance pickers, the
//  interview-type chips, the pad row, and the print documents.
//

@testable import CoderPad
import SwiftUI
import Testing

@MainActor
struct DesignSystemRenderTests {
    /// Rasterizes `view` at its ideal size and returns the produced image size,
    /// or `nil` if rendering failed entirely.
    private func renderSize(_ view: some View) -> CGSize? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage?.size
    }

    /// Asserts `view` renders to a non-empty raster.
    private func expectRenders(_ view: some View, _ label: Comment) {
        let size = renderSize(view)
        #expect(size != nil, label)
        #expect((size?.width ?? 0) > 0 && (size?.height ?? 0) > 0, label)
    }

    @Test func `state badge renders for every state`() {
        let states: [PadState] = [.active, .ended, .pending, .deleted, .other("queued")]
        for state in states {
            expectRenders(StateBadge(state: state), "StateBadge(\(state.rawValue))")
        }
    }

    @Test func `avatar circle from account renders`() {
        // The base AvatarCircle variants are covered in the package's RenderTests;
        // here we exercise the app-side `AvatarCircle(account:)` convenience.
        expectRenders(AvatarCircle(account: Account(name: "Acme", apiKey: "k",
                                                    iconSymbol: "briefcase.fill", tintHex: "#FF8800")),
                      "AvatarCircle from account")
    }

    @Test func `account symbol picker renders`() {
        expectRenders(AccountSymbolPicker(selection: .constant(nil)),
                      "AccountSymbolPicker with no selection")
        expectRenders(AccountSymbolPicker(selection: .constant("star.fill")),
                      "AccountSymbolPicker with a selection")
    }

    @Test func `account tint picker renders`() {
        expectRenders(AccountTintPicker(selection: .constant(nil), defaultColor: .accentColor),
                      "AccountTintPicker with default selection")
        expectRenders(AccountTintPicker(selection: .constant("#FF9500"), defaultColor: .accentColor),
                      "AccountTintPicker with a selection")
    }

    @Test func `appearance picker renders for every selection`() {
        for option in AppAppearance.allCases {
            expectRenders(AppearancePicker(selection: .constant(option.colorScheme)),
                          "AppearancePicker(\(option.rawValue))")
        }
    }

    @Test func `interview type chips render`() {
        for type in InterviewType.allCases {
            expectRenders(type.chip, "InterviewType.\(type.rawValue).chip")
        }
    }

    @Test func `pad row renders`() throws {
        // The pad row is now hosted inside the NSTableView-backed `FastList` as
        // `PadRowHostableContent` (#439) — dragging and selection are the table's
        // job, so the row renders the same whether or not the pad has a URL. A pad
        // with a title and one falling back to its id must both still rasterize.
        let withURL = try CoderPadClient.decoder.decode(
            Pad.self,
            from: Data(#"""
            {"id": "ABC123", "title": "Onsite", "state": "started", "url": "https://app.coderpad.io/ABC123"}
            """#.utf8)
        )
        let noURL = try CoderPadClient.decoder.decode(Pad.self, from: Data(#"{"id": "X1", "url": ""}"#.utf8))
        expectRenders(
            PadRowHostableContent(pad: withURL, ownerDisplay: "owner@x.co", isFavorite: false, onToggleFavorite: {})
                .frame(width: 320),
            "PadRowHostableContent with title"
        )
        expectRenders(
            PadRowHostableContent(pad: noURL, ownerDisplay: "", isFavorite: false, onToggleFavorite: {})
                .frame(width: 320),
            "PadRowHostableContent without title"
        )
    }

    @Test func `dense custom rows render at accessibility text sizes`() throws {
        let pad = try CoderPadClient.decoder.decode(
            Pad.self,
            from: Data(#"{"id":"A11Y","title":"A deliberately long interview title","state":"started"}"#.utf8)
        )
        expectRenders(
            PadRowHostableContent(
                pad: pad,
                ownerDisplay: "accessibility-reviewer@example.com",
                isFavorite: true,
                onToggleFavorite: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 340),
            "Pad row at accessibility5"
        )

        for state in [PadState.active, .ended, .pending, .deleted] {
            expectRenders(
                StateBadge(state: state)
                    .environment(\.dynamicTypeSize, .accessibility5),
                "StateBadge(\(state.rawValue)) at accessibility5"
            )
        }
    }

    @Test func `command editable title renders when clamped narrow`() {
        // The width clamp subtracts a reserve for the pencil, which in a narrow
        // layout used to leave the field zero-width (#2020).
        expectRenders(
            CommandEditableTitle(title: "A rather long pad title", clampsWidth: true,
                                 scope: .init(accountID: nil, itemID: "preview",
                                              title: "A rather long pad title"),
                                 editRequest: nil, onCommit: { _ in true })
                .frame(width: 24),
            "CommandEditableTitle clamped in a narrow layout"
        )
    }

    @Test func `question print document renders`() throws {
        // Populate every MarkdownText-backed section (description, candidate
        // instructions, solution) so the print document rasterizes each selectable
        // block. The print path sets `\.isRasterizedForPrint` so ImageRenderer doesn't
        // hit the un-flattenable text-selection overlay and log a fault (#582).
        let json = #"""
        {"id": 1, "title": "Two Sum", "language": "python3",
         "description": "Return the indices that sum to the **target**.",
         "candidate_instructions": [{"instructions": "Read the prompt.", "default_visible": true},
                                    {"instructions": "Then `solve` it.", "default_visible": true}],
         "contents": "def two_sum(nums, target):\n    pass",
         "solution": "Use a hash map."}
        """#
        let question = try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
        expectRenders(QuestionPrintDocument(question: question).frame(width: 480),
                      "QuestionPrintDocument candidate copy")
        expectRenders(QuestionPrintDocument(question: question, audience: .interviewer).frame(width: 480),
                      "QuestionPrintDocument interviewer copy")
    }

    @Test func `question detail sections render across widths and appearances`() async throws {
        let client = CoderPadClient.mock(key: "question-detail-render")
        let rich = try await client.getQuestion(id: 101)
        let empty = try await client.getQuestion(id: 104)
        let longMetadata = try question(
            rich,
            replacing: [
                "title": "Design a resilient multi-region interview scheduling and evaluation service",
                "author_name": "Alexandra Montgomery-Smythe, Principal Interview Architecture Lead",
                "organization_name": "International Distributed Systems Research and Hiring Cooperative"
            ]
        )

        for width in [340.0, 760.0] {
            for scheme in [ColorScheme.light, .dark] {
                let detail = QuestionDetailView(client: client, question: rich)
                let summaryDetail = QuestionDetailView(client: client, question: longMetadata)
                expectRenders(summaryDetail.summaryCard.frame(width: width).preferredColorScheme(scheme),
                              "Question summary \(width) \(scheme)")
                expectRenders(detail.testCasesCard.frame(width: width).preferredColorScheme(scheme),
                              "Question test cases \(width) \(scheme)")
                expectRenders(detail.starterCodeCards.frame(width: width).preferredColorScheme(scheme),
                              "Question starter code \(width) \(scheme)")
                let emptyDetail = QuestionDetailView(client: client, question: empty)
                expectRenders(emptyDetail.materialsPane.frame(width: width).preferredColorScheme(scheme),
                              "Question empty materials \(width) \(scheme)")
            }
        }
    }

    /// Derives edge-case presentation data from the package's public mock fixture,
    /// retaining all of its rich test cases and starter-code structure.
    private func question(_ fixture: Question, replacing values: [String: Any]) throws -> Question {
        let encoded = try JSONEncoder().encode(fixture)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.merge(values) { _, replacement in replacement }
        return try JSONDecoder().decode(
            Question.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    @Test func `question detail survives compact Spanish and right-to-left layouts`() async throws {
        let client = CoderPadClient.mock(key: "question-detail-locales")
        let question = try await client.getQuestion(id: 101)
        let detail = QuestionDetailView(client: client, question: question)
        expectRenders(
            detail.summaryCard
                .frame(width: 340)
                .environment(\.locale, Locale(identifier: "es")),
            "Question summary in compact Spanish"
        )
        expectRenders(
            detail.materialsPane
                .frame(width: 340)
                .environment(\.layoutDirection, .rightToLeft),
            "Question materials in compact RTL"
        )
        expectRenders(
            detail.materialsPane
                .frame(width: 340)
                .environment(\.dynamicTypeSize, .accessibility5),
            "Question materials at accessibility5"
        )
    }

    @Test func `pad print document renders`() throws {
        let json = #"""
        {"id": "ABC123", "title": "Onsite", "state": "ended", "owner_email": "owner@x.co",
         "language": "python3", "participants": ["Jane", "Joe"],
         "url": "https://app.coderpad.io/ABC123", "contents": "print(1)", "type": "live"}
        """#
        let pad = try CoderPadClient.decoder.decode(Pad.self, from: Data(json.utf8))
        let files = [PadPrintFile(id: "0", title: "main.py", code: "print(1)")]
        expectRenders(PadPrintDocument(pad: pad, files: files).frame(width: 480),
                      "PadPrintDocument")
    }
}
