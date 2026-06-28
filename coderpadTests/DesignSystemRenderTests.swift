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
            expectRenders(AppearancePicker(selection: .constant(option)),
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
            PadRowHostableContent(pad: withURL, ownerDisplay: "owner@x.co", favoritePads: .shared)
                .frame(width: 320),
            "PadRowHostableContent with title"
        )
        expectRenders(
            PadRowHostableContent(pad: noURL, ownerDisplay: "", favoritePads: .shared)
                .frame(width: 320),
            "PadRowHostableContent without title"
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
                      "QuestionPrintDocument")
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
