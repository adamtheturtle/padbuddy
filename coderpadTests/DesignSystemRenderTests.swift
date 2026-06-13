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

@testable import coderpad
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
    }

    @Test func `chip renders`() {
        expectRenders(Chip(text: "Python", systemImage: "chevron.left.slash.chevron.right"),
                      "Chip with icon")
        expectRenders(Chip(text: "No icon"), "Chip without icon")
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
}
