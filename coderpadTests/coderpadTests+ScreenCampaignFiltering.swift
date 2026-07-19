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
}
