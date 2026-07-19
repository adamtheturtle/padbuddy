//
//  coderpadTests+ScreenCampaignFiltering.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Screen campaign filtering")
struct ScreenCampaignFilteringTests {
    private let campaigns = [
        ScreenCampaign(id: 1, name: "Zulu"),
        ScreenCampaign(id: 2, name: "Alpha", pinned: true),
        ScreenCampaign(id: 3, name: "Archived Alpha", archived: true),
        ScreenCampaign(id: 4, name: "Beta")
    ]

    @Test
    func `filters archived and search then sorts pinned first`() {
        let visible = ScreenCampaignsView.filteredCampaigns(
            campaigns,
            search: "  A  ",
            showArchived: false,
            hasSelection: false
        )

        #expect(visible.map(\.id) == [2, 4])
    }

    @Test
    func `selection ignores search while archived preference still applies`() {
        let selected = ScreenCampaignsView.filteredCampaigns(
            campaigns,
            search: "no match",
            showArchived: false,
            hasSelection: true
        )
        let withArchived = ScreenCampaignsView.filteredCampaigns(
            campaigns,
            search: "alpha",
            showArchived: true,
            hasSelection: false
        )

        #expect(selected.map(\.id) == [2, 4, 1])
        #expect(withArchived.map(\.id) == [2, 3])
    }

    @Test
    func `campaign drag payload is structured sanitized and bounded`() {
        let remote = "\u{0000}\u{200D}  " + String(repeating: "a", count: 250) + "\n"
        let payload = ScreenCampaignDragPayload(campaign: ScreenCampaign(id: 42, name: remote))

        #expect(payload.id == 42)
        #expect(payload.name.count == ScreenCampaignDragPayload.maximumNameLength)
        #expect(payload.name.allSatisfy { !$0.isNewline && !$0.isWhitespace })
    }

    @Test
    func `campaign language summary bounds remote entries and marks overflow`() {
        let languages = [
            "python3", "javascript", "\u{0000}java\u{200D}",
            String(repeating: "x", count: 500), "go", "ruby", "ignored"
        ]

        let summary = ScreenCampaignRow.languageSummary(languages)

        #expect(summary.contains("Python"))
        #expect(summary.contains("More…"))
        #expect(!summary.contains("\u{0000}"))
        #expect(!summary.contains("\u{200D}"))
        #expect(!summary.contains("ignored"))
        #expect(summary.count < 180)
    }
}
