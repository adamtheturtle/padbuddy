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

struct RetryGate: Equatable {
    private(set) var isRunning = false

    mutating func begin() -> Bool {
        guard !isRunning else { return false }

        isRunning = true
        return true
    }

    mutating func finish() {
        isRunning = false
    }

    mutating func cancel() {
        isRunning = false
    }
}

enum FilterableListPresentation: Equatable {
    case initialLoading
    case emptyError
    case list
}

func filterableListPresentation(isLoading: Bool, isEmpty: Bool, hasError: Bool) -> FilterableListPresentation {
    if isEmpty, hasError { return .emptyError }
    if isEmpty, isLoading { return .initialLoading }
    return .list
}

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
    /// Optional context for the spinner. Keep empty for generic first-load states.
    let loadingMessage: String
    /// Retry handler for the error view's button.
    let onReload: () async -> Void
    /// The host's error view, given the error and a retry action (the host wires the
    /// retry to whatever button it draws). Keeps the domain-specific `APIErrorView`
    /// out of the design system.
    @ViewBuilder var errorView: (any Error, @escaping () -> Void) -> ErrorContent
    @ViewBuilder var savedSearches: () -> SavedSearches
    @ViewBuilder var filters: () -> Filters
    @ViewBuilder var list: () -> List
    @State private var retryGate = RetryGate()
    @State private var retryTask: Task<Void, Never>?

    public init(
        isLoading: Bool,
        isEmpty: Bool,
        error: (any Error)?,
        loadingMessage: String,
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
        content
            .onDisappear(perform: cancelRetry)
    }

    @ViewBuilder
    private var content: some View {
        switch filterableListPresentation(isLoading: isLoading, isEmpty: isEmpty, hasError: error != nil) {
        case .initialLoading:
            if loadingMessage.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView(loadingMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .emptyError:
            if let error {
                errorView(error, retry)
            }

        case .list:
            VStack(spacing: 0) {
                // With rows already on screen a failed (re)load previously stayed
                // completely silent, so a partially streamed list read as the full
                // organization. Surface a compact, non-blocking banner with a retry
                // instead of hiding the incompleteness (#1202).
                if let error {
                    inlineErrorBanner(error)
                    Divider()
                }
                savedSearches()
                filters()
                Divider()
                list()
            }
        }
    }

    private func inlineErrorBanner(_ error: any Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(verbatim: error.localizedDescription)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Retry", action: retry)
                .font(.callout)
                .disabled(retryGate.isRunning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func retry() {
        guard retryGate.begin() else { return }

        retryTask = Task {
            await onReload()
            guard !Task.isCancelled else { return }

            retryGate.finish()
            retryTask = nil
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retryGate.cancel()
    }
}
