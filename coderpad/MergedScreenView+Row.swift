//
//  MergedScreenView+Row.swift
//  coderpad
//
//  The combined Screen list's row view, copy text, and per-render row memo, split
//  out of MergedScreenView.swift to keep that file under the length limit.
//

import SwiftUI

/// Memo holding the merged Screen list's filtered + sorted rows for one render (#2118).
/// Mirrors `SortedQuestionsCache` in the merged questions list.
final class FilteredScreenCampaignsCache {
    var rows: [ScopedScreenCampaign] = []
}

extension ScopedScreenCampaign {
    var copyText: String {
        "\(campaign.name)\t\(account.name)"
    }
}

extension MergedScreenView {
    /// Responses and cached buckets only count while the account still uses these credentials.
    func credentialToken(_ account: Account) -> String {
        "\(account.screenApiKey ?? ""):\(account.screenRegion.rawValue)"
    }
}

/// One merged campaign row: the campaign's own row plus a label naming its source
/// account, matching the account tag on merged pad/question rows.
struct MergedScreenCampaignRow: View {
    let scoped: ScopedScreenCampaign

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScreenCampaignRow(campaign: scoped.campaign)
            AccountMetaLabel(account: scoped.account)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Merged campaign rows") {
    // Build the sample data in its own statements so the List ViewBuilder
    // expression stays under the 250ms type-check budget (warnings-as-errors
    // makes an overrun a fatal build error).
    let backend = ScopedScreenCampaign(
        accountID: UUID(), account: RowAccount(Account(name: "Acme", apiKey: "")),
        campaign: ScreenCampaign(id: 1, name: "Backend Engineer", languages: ["python"], pinned: true)
    )
    let frontend = ScopedScreenCampaign(
        accountID: UUID(), account: RowAccount(Account(name: "Globex", apiKey: "")),
        campaign: ScreenCampaign(id: 2, name: "Frontend Engineer", languages: ["javascript"])
    )
    List {
        MergedScreenCampaignRow(scoped: backend)
        MergedScreenCampaignRow(scoped: frontend)
    }
    .frame(width: 460, height: 200)
}
