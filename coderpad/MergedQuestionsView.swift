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
    /// While offline the app is read-only, so create/edit/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    @State var accounts = AccountsStore.shared
    @State var router = MergedRouting.shared
    @State var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var nav = AppNavigation.shared
    @State var questionsByAccount: [UUID: [Question]] = [:]
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false

    @Binding var selection: Question?
    /// The primary row, keyed by the account-namespaced row id (`AccountScoped.id`)
    /// rather than the bare per-org question id, which two accounts routinely share.
    /// Derived from `selectedRowIDs` and bridged to the `Question` `selection` below.
    @State var selectedRowID: String?
    /// The List's selection. A set so several rows can be selected to copy their
    /// links at once; `selectedRowID`/`selection` track the primary within it.
    @State var selectedRowIDs: Set<String> = []
    /// Whether the saved selection has been restored this session. Gates persistence
    /// so the empty startup state never clobbers the stored row id, and keeps the
    /// restore to once, mirroring `QuestionsView`.
    @State var didRestoreSelection = false
    /// A one-shot request to scroll the restored row into view on launch; a `List`
    /// won't scroll to a programmatic selection on its own. Consumed and cleared by
    /// the `ScrollViewReader` in the list.
    @State var pendingScrollToRowID: String?
    /// Whether the saved filters have been restored this session. Gates persistence
    /// so the empty startup state never clobbers a saved snapshot, mirroring `QuestionsView`.
    @State var didRestoreFilters = false
    /// Rows queued for a multi-row delete (carrying their source account, so each
    /// deletes against the right client), awaiting the confirmation dialog, plus the
    /// error from a failed delete. Single-row delete is delegated to the detail view.
    @State var rowsPendingBulkDelete: [AccountScoped<Question>]?
    @State var bulkDeleteError: String?
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
