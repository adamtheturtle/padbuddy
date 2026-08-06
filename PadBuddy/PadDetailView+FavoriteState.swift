//
//  PadDetailView+FavoriteState.swift
//  coderpad
//

extension PadDetailView {
    var isFavorite: Bool {
        favorites.isFavorite(pad.id, account: owningAccountID)
    }

    var focusedFavoriteState: FocusedPadFavoriteState {
        .init(padID: pad.id, accountID: owningAccountID, isFavorite: isFavorite)
    }

    func toggleFavorite() {
        guard let account = owningAccountID else { return }

        favorites.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
    }
}
