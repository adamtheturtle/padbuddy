//
//  RenderTests.swift
//  CoderPadDesignSystemTests
//
//  The generic subset of the app's DesignSystemRenderTests (#377), ported here so
//  the shared primitives are covered in the package that owns them — independent of
//  the app target. Like the app version, these use SwiftUI's `ImageRenderer` to
//  confirm each primitive rasterizes to a valid, non-zero image rather than
//  pixel-comparing against fragile reference snapshots: that catches the common
//  regressions (a primitive that crashes when rendered, or collapses to zero size)
//  with no third-party dependency and nothing to keep in sync. App-coupled
//  primitives (StateBadge on PadState, the print documents, the account pickers)
//  stay in the app's render tests.
//

@testable import CoderPadDesignSystem
import SwiftUI
import Testing

@MainActor
struct RenderTests {
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

    @Test func `avatar circle renders`() {
        expectRenders(AvatarCircle(label: "Jane Doe"), "AvatarCircle with a name")
        // Empty label falls back to "?" — still must render.
        expectRenders(AvatarCircle(label: ""), "AvatarCircle with empty label")
        // The symbol + tint variant (custom account icon) must also rasterize.
        expectRenders(AvatarCircle(label: "Acme", tint: .orange, symbol: "star.fill"),
                      "AvatarCircle with symbol")
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
}
