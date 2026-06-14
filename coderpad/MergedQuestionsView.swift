//
//  MergedQuestionsView.swift
//  coderpad
//
//  The combined "All Accounts" questions list: every real account's questions in
//  one merged, sorted list with per-account badges. Mirrors `MergedPadsView`;
//  per-row actions and the detail pane route to the originating account through
//  `MergedRouting`. View-building members live in `+List`/`+Bars`/`+Logic`
//  extensions to keep this declaration within the `type_body_length` budget.
//

import AppKit
import SwiftUI

struct MergedQuestionsView: View {
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    @State var accounts = AccountsStore.shared
    @State var router = MergedRouting.shared
    @State var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var nav = AppNavigation.shared
    @State var questionsByAccount: [UUID: [Question]] = [:]
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false

    @Binding var selection: Question?
    /// The List's selection, keyed by the account-namespaced row id
    /// (`AccountScoped.id`) rather than the bare per-org question id, which two
    /// accounts routinely share. Bridged to the `Question` `selection` below.
    @State var selectedRowID: String?
    /// List vs. Table presentation, sharing `QuestionsView`'s preference key so the
    /// choice is consistent across the single-account and combined question lists.
    /// Defaults to List, so the standard experience is unchanged.
    @AppStorage(QuestionListPresentation.storageKey) var presentation: QuestionListPresentation = .list
    /// The Table's active column sort, applied to the rows in `questionsTable`. Starts
    /// empty so the table opens in the merged list's order; clicking a header drives
    /// it. Empty rather than a default `KeyPathComparator` because a key-path literal
    /// isn't `Sendable` in the `@State` macro's stored default under Swift 6.
    @State var sortOrder: [KeyPathComparator<AccountScoped<Question>>] = []
    @Binding var search: String

    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var accountFilter: UUID?
    @State var mineOnly = false
    @State var favoritesOnly = false
    @AppStorage(QuestionSort.storageKey) var sort: QuestionSort = .lastUsedDesc
    @State var creatingForAccount: Account?

    /// Per-render memo for the combined cross-account rows (`scoped`), refreshed
    /// once at the top of `body` so its many readers (filter pass, chip options,
    /// counts, empty-state checks) share a single build, matching `MergedPadsView`.
    @State var scopedCache = ScopedQuestionsCache()
    /// Per-render memo for the filtered + sorted rows (`sorted`), so the list,
    /// overlay, and count bar share one filter+sort pass instead of redoing it on
    /// every read — the hitch the pads view was already rewritten to avoid.
    @State var sortedCache = SortedQuestionsCache()

    var body: some View {
        // Recompute the combined rows and the filtered+sorted rows once per render;
        // every read below hits the memos.
        refreshScoped()
        refreshSorted()
        return decorated
    }
}

/// Memo holding the merged questions list's combined rows for one render.
final class ScopedQuestionsCache {
    var rows: [AccountScoped<Question>] = []
}

/// Memo holding the merged questions list's filtered + sorted rows for one render.
final class SortedQuestionsCache {
    var rows: [AccountScoped<Question>] = []
}
