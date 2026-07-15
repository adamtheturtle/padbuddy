//
//  ScreenTestsView+Support.swift
//  coderpad
//
//  Supporting types for `ScreenTestsView`, split out to keep that file under the
//  400-line limit: the delete/action alerts modifier and the server-side date-range
//  filter (#443).
//

import SwiftUI

/// The test-sessions list's delete confirmation and the two action alerts, extracted
/// into a modifier so `ScreenTestsView.body` stays under the Release build's 250ms
/// type-check budget (#443). `onDelete` carries the row action back to the view.
struct ScreenTestActionAlerts: ViewModifier {
    @Binding var testPendingDelete: ScreenTestSession?
    @Binding var actionError: String?
    @Binding var showResentConfirmation: Bool
    let onDelete: (ScreenTestSession) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete this test session?",
                isPresented: .init(get: { testPendingDelete != nil },
                                   set: { if !$0 { testPendingDelete = nil } }),
                presenting: testPendingDelete
            ) { test in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { onDelete(test) }
            } message: { _ in
                Text("This permanently removes the candidate's test session. This can't be undone.")
            }
            .alert("Couldn't complete that action",
                   isPresented: .init(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .alert("Invitation resent", isPresented: $showResentConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The candidate was emailed their invitation again.")
            }
    }
}

/// A coarse, server-side date window for the test-sessions fetch (#443), mapped to the
/// Screen API's `from` lower bound. `.all` sends no bound (every session).
enum ScreenTestDateRange: String, CaseIterable, Identifiable {
    case all
    case last7
    case last30
    case last90

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .all: String(localized: "All time")
        case .last7: String(localized: "Last 7 days")
        case .last30: String(localized: "Last 30 days")
        case .last90: String(localized: "Last 90 days")
        }
    }

    /// The window's lower-bound date relative to now, or `nil` for "all time".
    var lowerBound: Date? {
        let days: Double
        switch self {
        case .all: return nil
        case .last7: days = 7
        case .last30: days = 30
        case .last90: days = 90
        }
        return Date(timeIntervalSinceNow: -days * 24 * 60 * 60)
    }
}
