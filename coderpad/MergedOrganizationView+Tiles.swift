//
//  MergedOrganizationView+Tiles.swift
//  coderpad
//
//  The aggregate stat tile used by `MergedOrganizationView`'s cross-account
//  header grid. Split out to keep the view file within the file-length limit.
//

import Foundation
import SwiftUI

nonisolated enum AggregateCoverage: Equatable {
    case complete(total: Int)
    case loading(missing: Int, total: Int)
    case incomplete(missing: Int, total: Int)

    static func resolve(
        eligibleIDs: Set<UUID>, loadedIDs: Set<UUID>, failedIDs: Set<UUID>
    ) -> Self {
        let failed = failedIDs.intersection(eligibleIDs)
        let usable = loadedIDs.intersection(eligibleIDs).subtracting(failed)
        let missing = max(0, eligibleIDs.count - usable.count)
        if !failed.isEmpty { return .incomplete(missing: missing, total: eligibleIDs.count) }
        if missing > 0 { return .loading(missing: missing, total: eligibleIDs.count) }
        return .complete(total: eligibleIDs.count)
    }

    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    func accessibilityValue(_ value: String) -> String {
        switch self {
        case let .complete(total):
            String(localized: "\(value), complete across \(total) accounts.")
        case let .loading(missing, total):
            String(localized: "Unavailable, loading \(missing) of \(total) accounts.")
        case let .incomplete(missing, total):
            String(localized: "Unavailable, data missing for \(missing) of \(total) accounts.")
        }
    }
}

/// One tile in the combined Organization view's aggregate header: an icon, an
/// uppercase caption title, and the summed value.
struct AggregateStatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color
    let coverage: AggregateCoverage

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(coverage.accessibilityValue(value))
    }
}
