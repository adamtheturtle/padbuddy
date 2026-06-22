//
//  FilterableListView.swift
//  CoderPadDesignSystem
//
//  The shared scaffold for a filtered list column — a centered spinner on the very
//  first load, a host-supplied error view when that load fails with nothing cached,
//  and otherwise a saved-searches bar over a filter bar over the list. Lifted out of
//  the app (#515) so both apps' list columns share one structure and can't drift.
//
//  Only the structural scaffold lives here. Each section's saved-search bar, filter
//  bar, list, and error view are genuinely type-specific (different filters, row
//  types, id types, and a domain-specific API error view), so they're supplied as
//  builders; the section-count subtitle and the column toolbar likewise stay at the
//  call site, where they differ.
//

import SwiftUI

public struct FilterableListView<
    ErrorContent: View, SavedSearches: View, Filters: View, List: View
>: View {
    /// True while a load is in flight. Paired with `isEmpty` so the spinner shows
    /// only on the very first load, never over already-rendered (cached) rows.
    let isLoading: Bool
    /// Whether the backing list is empty, which gates both the spinner and the error
    /// view: with content already on screen, a transient error or refresh stays quiet.
    let isEmpty: Bool
    /// The last load error, surfaced (via the injected error view) only when nothing
    /// is loaded.
    let error: (any Error)?
    /// The spinner's label, e.g. "Loading pads…".
    let loadingMessage: LocalizedStringKey
    /// Retry handler for the error view's button.
    let onReload: () async -> Void
    /// The host's error view, given the error and a retry action (the host wires the
    /// retry to whatever button it draws). Keeps the domain-specific `APIErrorView`
    /// out of the design system.
    @ViewBuilder var errorView: (any Error, @escaping () -> Void) -> ErrorContent
    @ViewBuilder var savedSearches: () -> SavedSearches
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var list: () -> List

    public init(
        isLoading: Bool,
        isEmpty: Bool,
        error: (any Error)?,
        loadingMessage: LocalizedStringKey,
        onReload: @escaping () async -> Void,
        @ViewBuilder errorView: @escaping (any Error, @escaping () -> Void) -> ErrorContent,
        @ViewBuilder savedSearches: @escaping () -> SavedSearches,
        @ViewBuilder filters: @escaping () -> Filters,
        @ViewBuilder list: @escaping () -> List
    ) {
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.error = error
        self.loadingMessage = loadingMessage
        self.onReload = onReload
        self.errorView = errorView
        self.savedSearches = savedSearches
        self.filters = filters
        self.list = list
    }

    public var body: some View {
        if isLoading, isEmpty {
            ProgressView(loadingMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, isEmpty {
            errorView(error) { Task { await onReload() } }
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
