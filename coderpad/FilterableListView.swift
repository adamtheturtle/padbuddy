//
//  FilterableListView.swift
//  coderpad
//
//  The shared scaffold for the Pads and Questions list columns. Both sections
//  presented the same three-state structure by hand — a centered spinner while the
//  first load is in flight, the API error view when that load fails with nothing
//  cached, and otherwise a saved-searches bar over a filter bar over the list. This
//  factors that arrangement into one place so the two columns can't drift.
//
//  Only the structural scaffold lives here. Each section's saved-search bar, filter
//  bar, and list are genuinely type-specific (different filters, row types, and id
//  types), so they're supplied as builders; the section-count subtitle and the
//  column toolbar likewise stay at the call site, where they differ.
//

import SwiftUI

struct FilterableListView<SavedSearches: View, Filters: View, List: View>: View {
    /// True while a load is in flight. Paired with `isEmpty` so the spinner shows
    /// only on the very first load, never over already-rendered (cached) rows.
    let isLoading: Bool
    /// Whether the backing list is empty, which gates both the spinner and the error
    /// view: with content already on screen, a transient error or refresh stays quiet.
    let isEmpty: Bool
    /// The last load error, surfaced (via `APIErrorView`) only when nothing is loaded.
    let error: (any Error)?
    /// The spinner's label, e.g. "Loading pads…".
    let loadingMessage: LocalizedStringKey
    /// Retry handler for the error view's button.
    let onReload: () async -> Void
    @ViewBuilder var savedSearches: () -> SavedSearches
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var list: () -> List

    var body: some View {
        if isLoading, isEmpty {
            ProgressView(loadingMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, isEmpty {
            APIErrorView(error: error) { Task { await onReload() } }
        } else {
            VStack(spacing: 0) {
                savedSearches()
                filters()
                Divider()
                list()
            }
        }
    }
}
