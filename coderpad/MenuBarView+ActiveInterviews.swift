#if os(macOS)
    //
    //  MenuBarView+ActiveInterviews.swift
    //  coderpad
    //

    import SwiftUI

    extension MenuBarView {
        /// A glanceable list of interviews that are live right now (#593), with an
        /// explicit freshness state until every contributing account has refreshed.
        @ViewBuilder
        func activeInterviewItems() -> some View {
            let live = activePads
            if !live.isEmpty {
                Text("Active Interviews")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = Self.activeInterviewFreshnessStatus(
                    accountIDs: Set(live.map(\.account.id)),
                    freshAccountIDs: freshPadAccounts,
                    isLoading: isLoading,
                    hasRefreshError: errorMessage != nil
                ) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.orange)
                }
                ForEach(live.prefix(topCount)) { row in
                    padHandoffMenu(
                        row,
                        title: padRowLabel(row),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
                if live.count > topCount {
                    Text("…\(live.count - topCount) more").foregroundStyle(.secondary)
                }
                Divider()
            }
        }

        nonisolated static func activeInterviewFreshnessStatus(
            accountIDs: Set<UUID>,
            freshAccountIDs: Set<UUID>,
            isLoading _: Bool,
            hasRefreshError: Bool
        ) -> String? {
            guard !accountIDs.isSubset(of: freshAccountIDs), hasRefreshError else { return nil }

            return "Refresh failed — cached data may be stale"
        }
    }
#endif
