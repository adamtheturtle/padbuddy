//
//  PadBuddyTests+DetailChipBar.swift
//  PadBuddyTests
//

@testable import PadBuddy
import SwiftUI
import Testing

/// A stand-in chip item so the bar's de-duplication can be tested without
/// depending on the real section/pane enums, which can't repeat a value.
private struct TestChipItem: DetailChipItem {
    let id: String

    var label: LocalizedStringKey {
        LocalizedStringKey(id)
    }

    var systemImage: String {
        "circle"
    }
}

@Suite("Detail chip bar")
@MainActor
struct DetailChipBarTests {
    private func bar(ids: [String]) -> DetailChipBar<TestChipItem> {
        DetailChipBar(items: ids.map(TestChipItem.init(id:)),
                      horizontalPadding: 0,
                      accessibilityLabel: "Sections") { _ in }
    }

    @Test
    func `repeated items render one chip each`() {
        #expect(bar(ids: ["overview", "code", "overview", "code"]).uniqueItems.map(\.id)
            == ["overview", "code"])
    }

    @Test
    func `distinct items keep the caller's ordering`() {
        #expect(bar(ids: ["code", "overview", "history"]).uniqueItems.map(\.id)
            == ["code", "overview", "history"])
    }
}
