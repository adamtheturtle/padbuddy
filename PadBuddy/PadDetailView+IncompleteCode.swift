//
//  PadDetailView+IncompleteCode.swift
//  coderpad
//
//  The incomplete-code warning shown above the code cards when one or more
//  environment fetches failed (#713). In its own file to keep the sections
//  file under the length lint.
//

import SwiftUI

extension PadDetailView {
    /// Shown above the code cards when one or more environment fetches failed:
    /// the surviving cards would otherwise read as the pad's complete code, and
    /// print/Save All Code would export the truncated set without warning (#713).
    var incompleteCodeWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(incompleteCodeMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
            // Inline recovery, mirroring the events failure card: disabled (with
            // progress) while a retry is in flight so clicks can't stack requests.
            HStack(spacing: 8) {
                Button("Retry") { Task { await load(visibleRefreshControls: true) } }
                    .controlSize(.small)
                    .disabled(isRefreshing)
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var incompleteCodeMessage: String {
        if environmentListWasTruncated {
            return String(
                localized: """
                The pad contains too many file environments to load safely, \
                so the code shown here is incomplete.
                """
            )
        }
        return String(
            localized: """
            ^[\(failedEnvironmentIDs.count) file environment](inflect: true) could not be loaded, \
            so the code shown here may be incomplete.
            """
        )
    }
}
