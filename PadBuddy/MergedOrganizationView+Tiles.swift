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
        if !failed.isEmpty {
            return .incomplete(missing: missing, total: eligibleIDs.count)
        }
        if missing > 0 {
            return .loading(missing: missing, total: eligibleIDs.count)
        }
        return .complete(total: eligibleIDs.count)
    }

    func displayValue(_ value: String) -> String {
        switch self {
        case .loading: "—"
        case .complete, .incomplete: value
        }
    }

    func accessibilityValue(_ value: String) -> String {
        switch self {
        case let .complete(total):
            String(localized: "\(value), complete across \(total) accounts.")
        case let .loading(missing, total):
            String(localized: "Unavailable, loading \(missing) of \(total) accounts.")
        case let .incomplete(missing, total):
            String(localized: "\(value), excluding \(missing) of \(total) accounts.")
        }
    }
}

/// A top-level warning for merged totals that omit accounts whose organization or
/// stats requests failed.
struct AggregateFailureBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(.orange.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some accounts could not refresh.")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            RetryCooldownButton(title: "Try Again", action: retry)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.orange.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
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
