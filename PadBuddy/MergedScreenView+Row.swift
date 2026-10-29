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
        "\(campaign.screenDisplayName)\t\(ExternalText.singleLine(account.name, limit: 128))"
    }
}

extension MergedScreenView {
    /// Responses and cached buckets only count while the account still uses these credentials.
    func credentialToken(_ account: Account) -> String {
        if account.isMock {
            return "mock:\(account.apiKey):\(account.isBadKeyDemo)"
        }

        return "\(account.screenApiKey ?? ""):\(account.screenRegion.rawValue)"
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
    // `ScreenCampaign`'s memberwise init validates its id and name, so the samples
    // are built with `try?` and the preview renders whichever survive.
    let backendCampaign = try? ScreenCampaign(
        id: 1, name: "Backend Engineer", languages: ["python"], pinned: true
    )
    let frontendCampaign = try? ScreenCampaign(id: 2, name: "Frontend Engineer", languages: ["javascript"])
    let backend = backendCampaign.map {
        ScopedScreenCampaign(
            accountID: UUID(), account: RowAccount(Account(name: "Acme", apiKey: "")), campaign: $0
        )
    }
    let frontend = frontendCampaign.map {
        ScopedScreenCampaign(
            accountID: UUID(), account: RowAccount(Account(name: "Globex", apiKey: "")), campaign: $0
        )
    }
    List {
        if let backend {
            MergedScreenCampaignRow(scoped: backend)
        }
        if let frontend {
            MergedScreenCampaignRow(scoped: frontend)
        }
    }
    .frame(width: 460, height: 200)
}
