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
    @Binding var actionErrors: [ScreenActionFailure]
    @Binding var actionErrorPresented: Bool
    @Binding var showResentConfirmation: Bool
    let onDelete: (ScreenTestSession) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete this test session?",
                isPresented: .init(get: { testPendingDelete != nil },
                                   set: {
                                       if !$0 {
                                           testPendingDelete = nil
                                       }
                                   }),
                presenting: testPendingDelete
            ) { test in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { onDelete(test) }
            } message: { _ in
                Text("This permanently removes the candidate's test session. This cannot be undone.")
            }
            .alert("Could not complete that action",
                   isPresented: .init(get: { actionErrorPresented && !actionErrors.isEmpty },
                                      set: {
                                          if !$0 {
                                              dismissFirstError()
                                          }
                                      })) {
                Button("Copy Diagnostic") {
                    if let detail = actionErrors.first?.detail {
                        Clipboard.copy(detail)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionErrors.first?.detail ?? "")
            }
            .alert("Invitation resent", isPresented: $showResentConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The candidate was emailed their invitation again.")
            }
    }

    private func dismissFirstError() {
        actionErrorPresented = false
        guard !actionErrors.isEmpty else { return }

        actionErrors.removeFirst()
        guard !actionErrors.isEmpty else { return }

        Task { @MainActor in
            await Task.yield()
            actionErrorPresented = true
        }
    }
}

struct ScreenActionFailure: Equatable {
    let operation: String
    let testID: Int
    let candidate: String
    let accountName: String?
    let reason: String

    var detail: String {
        let target = String(localized: "\(candidate) (session #\(testID))")
        let scope = accountName.map { String(localized: " in account “\($0)”") } ?? ""
        return String(localized: "\(operation) failed for \(target)\(scope).\n\n\(reason)")
    }
}

/// A coarse, server-side date window for the test-sessions fetch (#443), mapped to the
/// Screen API's bounded `from` / `to` window. `.all` sends no bounds (every session).
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

    /// A stable millisecond window relative to one captured reference instant.
    /// Both endpoints come from that same instant so retries cannot drift or admit
    /// future-dated sessions (#1473, #1474).
    func bounds(relativeTo referenceDate: Date) -> (from: Int?, until: Int?) {
        let days: Double
        switch self {
        case .all: return (nil, nil)
        case .last7: days = 7
        case .last30: days = 30
        case .last90: days = 90
        }
        let until = Int(referenceDate.timeIntervalSince1970 * 1000)
        let from = Int(referenceDate.addingTimeInterval(-days * 24 * 60 * 60).timeIntervalSince1970 * 1000)
        return (from, until)
    }
}
