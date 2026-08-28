//
//  FavoriteLimitAlert.swift
//  coderpad
//
//  Surfaces a refused star. The per-account caps used to be applied only on decode,
//  so starring past `maxEntriesPerAccount` looked like it worked and the extra
//  entries vanished on the next launch (#4788). The caps are now enforced where the
//  entry is added, which means the refusal has to be visible.
//

import SwiftUI

extension View {
    /// Presents whichever favorites store has refused a star. Both notices share one
    /// alert: only one can be raised per interaction, and stacking two alerts for the
    /// same cap would be worse than showing the one the user just hit.
    func favoriteLimitAlert(
        pads: FavoritePadsStore = .shared,
        questions: FavoriteQuestionsStore = .shared
    ) -> some View {
        modifier(FavoriteLimitAlert(pads: pads, questions: questions))
    }
}

private struct FavoriteLimitAlert: ViewModifier {
    @State var pads: FavoritePadsStore
    @State var questions: FavoriteQuestionsStore

    private var message: String? {
        pads.limitNotice ?? questions.limitNotice
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { presented in
                guard !presented else { return }

                dismiss()
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert("Favorites Limit Reached", isPresented: isPresented) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(message ?? "")
            }
    }

    /// Clears both, not just the one being shown: a notice left set would suppress
    /// the next refusal, which is the failure the alert exists to make visible.
    private func dismiss() {
        pads.limitNotice = nil
        questions.limitNotice = nil
    }
}
