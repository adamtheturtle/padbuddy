//
//  QuotaView+RefreshTimestamp.swift
//  coderpad
//

import SwiftUI

extension QuotaView {
    @ViewBuilder
    var quotaRefreshTimestamp: some View {
        if let lastSuccessfulRefresh {
            Text("Updated \(lastSuccessfulRefresh.formatted(SharedDateStyles.longDateAndTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Quota last refreshed \(lastSuccessfulRefresh.formatted(SharedDateStyles.longDateAndTime))"
                )
        }
    }
}
