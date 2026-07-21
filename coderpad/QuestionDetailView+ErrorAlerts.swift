//
//  QuestionDetailView+ErrorAlerts.swift
//  coderpad
//
//  Split from QuestionDetailView.swift to keep that file under the
//  file-length limit.
//

import SwiftUI

/// The detail view's save/delete failure alerts, pulled into a `ViewModifier` so
/// they don't inflate the `core` view body's type-check time past the warnings-as-errors
/// limit. Pad-creation failures use an inline retry banner instead.
/// Internal rather than private now that it lives in its own file.
struct QuestionDetailErrorAlerts: ViewModifier {
    @Binding var editError: String?
    @Binding var deleteError: String?

    func body(content: Content) -> some View {
        content
            .alert("Could not save question",
                   isPresented: Binding(get: { editError != nil },
                                        set: { if !$0 { editError = nil } })) {
                Button("OK", role: .cancel) { editError = nil }
            } message: {
                if let editError { Text(editError) }
            }
            .alert("Could not delete question",
                   isPresented: Binding(get: { deleteError != nil },
                                        set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                if let deleteError { Text(deleteError) }
            }
    }
}
