//
//  DesignSystemRenderTests.swift
//  coderpadTests
//
//  Render ("snapshot") coverage for the design-system primitives. Rather than
//  pixel-comparing against committed reference images — which are fragile across
//  OS/font-rendering changes and need recording/maintenance — these use SwiftUI's
//  built-in `ImageRenderer` to confirm each primitive rasterizes to a valid,
//  non-zero image. That guards against the common regressions (a primitive that
//  crashes when rendered, or collapses to zero size) with no third-party
//  dependency and nothing to keep in sync.
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

    @Test func `avatar circle renders`() {
        expectRenders(AvatarCircle(label: "Jane Doe"), "AvatarCircle with a name")
        // Empty label falls back to "?" — still must render.
        expectRenders(AvatarCircle(label: ""), "AvatarCircle with empty label")
        // The symbol + tint variant (custom account icon) must also rasterize.
        expectRenders(AvatarCircle(label: "Acme", tint: .orange, symbol: "star.fill"),
                      "AvatarCircle with symbol")
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

    @Test func `chip renders`() {
        expectRenders(Chip(text: "Python", systemImage: "chevron.left.slash.chevron.right"),
                      "Chip with icon")
        expectRenders(Chip(text: "No icon"), "Chip without icon")
    }

    @Test func `appearance picker renders for every selection`() {
        for option in AppAppearance.allCases {
            expectRenders(AppearancePicker(selection: .constant(option)),
                          "AppearancePicker(\(option.rawValue))")
        }
    }

    @Test func `meta label renders`() {
        expectRenders(MetaLabel(text: "Cursor", systemImage: "person.crop.circle"),
                      "MetaLabel with icon")
        expectRenders(MetaLabel(text: "Python"), "MetaLabel without icon")
    }

    @Test func `interview type chips render`() {
        for type in InterviewType.allCases {
            expectRenders(type.chip, "InterviewType.\(type.rawValue).chip")
        }
    }

    @Test func `card renders`() {
        expectRenders(Card { Text("Body") }, "Card wrapping content")
    }

    @Test func `detail section renders`() {
        expectRenders(
            DetailSection(title: "Details", systemImage: "info.circle") {
                LabeledRow(label: "Created", value: "1 Jan 2026").frame(width: 240)
            },
            "DetailSection without trailing"
        )
        expectRenders(
            DetailSection(title: "Events", systemImage: "list.bullet.rectangle") {
                ProgressView().controlSize(.small)
            } content: {
                Text("No events yet.")
            }
            .frame(width: 240),
            "DetailSection with trailing accessory"
        )
    }

    @Test func `section header renders`() {
        expectRenders(SectionHeader(title: "Pads", systemImage: "doc.text"), "SectionHeader with icon")
        expectRenders(SectionHeader(title: "Pads"), "SectionHeader without icon")
    }

    @Test func `labeled row renders`() {
        expectRenders(LabeledRow(label: "Pad ID", value: "DEMOABC1").frame(width: 240),
                      "LabeledRow")
        expectRenders(LabeledRow(label: "URL", value: "https://app.coderpad.io/x", monospaced: true)
            .frame(width: 240),
            "LabeledRow monospaced")
    }

    @Test func `stat tile renders`() {
        // StatTile fills the available width, so give it a width to size against.
        expectRenders(StatTile(title: "Pads created", value: "42", systemImage: "doc.text")
            .frame(width: 200),
            "StatTile")
    }

    @Test func `pad row renders, draggable and not`() throws {
        // A pad with a parseable URL takes the `.draggable` branch; one without
        // falls back to the plain row. Both must still rasterize.
        let withURL = try CoderPadClient.decoder.decode(
            Pad.self,
            from: Data(#"{"id": "ABC123", "title": "Onsite", "state": "started", "url": "https://app.coderpad.io/ABC123"}"#.utf8)
        )
        let noURL = try CoderPadClient.decoder.decode(Pad.self, from: Data(#"{"id": "X1", "url": ""}"#.utf8))
        expectRenders(PadRow(pad: withURL).frame(width: 320), "PadRow draggable")
        expectRenders(PadRow(pad: noURL).frame(width: 320), "PadRow without URL")
    }

    @Test func `question print document renders`() throws {
        let json = #"""
        {"id": 1, "title": "Two Sum", "language": "python3",
         "description": "Return the indices that sum to the target.",
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
