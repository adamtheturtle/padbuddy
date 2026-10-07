import SwiftUI

extension ScreenTestDetailView {
    func reportActivity(_ report: ScreenReport) -> some View {
        ScreenResultRowsView(rows: [
            ScreenResultRows.value(
                String(localized: "Marked as cheated by recruiter"),
                report.markedAsCheatedByRecruiter
            ),
            ScreenResultRows.value(
                String(localized: "Time outside environment (seconds)"),
                report.timeSpentOutsideEnvironmentSeconds
            ),
            ScreenResultRows.value(String(localized: "Environment exit count"), report.environmentExitCount)
        ])
    }
}
