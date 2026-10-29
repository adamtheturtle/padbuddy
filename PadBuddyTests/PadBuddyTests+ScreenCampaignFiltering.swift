//
//  PadBuddyTests+ScreenCampaignFiltering.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Screen campaign filtering")
struct ScreenCampaignFilteringTests {
    /// Built through the throwing memberwise init, which validates each id and name.
    private func campaigns() throws -> [ScreenCampaign] {
        try [
            ScreenCampaign(id: 1, name: "Zulu"),
            ScreenCampaign(id: 2, name: "Alpha", pinned: true),
            ScreenCampaign(id: 3, name: "Archived Alpha", archived: true),
            ScreenCampaign(id: 4, name: "Beta")
        ]
    }

    @Test
    func `filters archived and search then sorts pinned first`() throws {
        let visible = try ScreenCampaignsView.filteredCampaigns(
            campaigns(),
            search: "  A  ",
            showArchived: false,
            hasSelection: false
        )

        #expect(visible.map(\.id) == [2, 4])
    }

    @Test
    func `selection ignores search while archived preference still applies`() throws {
        let selected = try ScreenCampaignsView.filteredCampaigns(
            campaigns(),
            search: "no match",
            showArchived: false,
            hasSelection: true
        )
        let withArchived = try ScreenCampaignsView.filteredCampaigns(
            campaigns(),
            search: "alpha",
            showArchived: true,
            hasSelection: false
        )

        #expect(selected.map(\.id) == [2, 4, 1])
        #expect(withArchived.map(\.id) == [2, 3])
    }

    @Test func `duplicate campaign ids deterministically keep the first row`() throws {
        let campaigns = try [
            ScreenCampaign(id: 7, name: "First"),
            ScreenCampaign(id: 8, name: "Other"),
            ScreenCampaign(id: 7, name: "Duplicate")
        ]

        let unique = ScreenCampaignsView.deduplicatedCampaigns(campaigns)

        #expect(unique.map(\.id) == [7, 8])
        #expect(unique.first?.name == "First")
    }

    @Test func `campaign search keys are bounded before normalization and sorting`() throws {
        let remote = "A\n\u{202E}" + String(repeating: "Z", count: 10000)
        let index = try ScreenCampaignsView.makeCampaignSearchIndex([ScreenCampaign(id: 9, name: remote)])
        #expect(index[0].foldedName.unicodeScalars.count <= 200)
        #expect(index[0].foldedName.hasPrefix("a "))
        #expect(!index[0].foldedName.contains("\u{202E}"))
    }

    @Test func `campaign retention caps the collection before indexing and reports omissions`() throws {
        let campaigns = try (1 ... 1005).map { try ScreenCampaign(id: $0, name: "Campaign \($0)") }
        let retained = ScreenCampaignsView.retainedCampaigns(campaigns)
        #expect(retained.campaigns.count == 1000)
        #expect(retained.omitted == 5)
        #expect(retained.campaigns.last?.id == 1000)
        #expect(ScreenCampaignsView.makeCampaignSearchIndex(campaigns).count == 1000)
    }

    @Test func `refresh failure preserves a selection present in stale rows`() throws {
        let campaigns = try campaigns()

        #expect(ScreenCampaignsView.selectionAfterRefreshFailure(2, campaigns: campaigns) == 2)
        #expect(ScreenCampaignsView.selectionAfterRefreshFailure(99, campaigns: campaigns) == nil)
    }

    @Test
    func `campaign drag payload is structured sanitized and bounded`() throws {
        let remote = "\u{0000}\u{200D}  " + String(repeating: "a", count: 250) + "\n"
        let payload = try ScreenCampaignDragPayload(campaign: ScreenCampaign(id: 42, name: remote))

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
