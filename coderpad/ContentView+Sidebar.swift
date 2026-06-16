//
//  ContentView+Sidebar.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Binding var section: AppSection
    @Environment(\.colorScheme) private var colorScheme
    @State private var accounts = AccountsStore.shared
    @State private var savedSearches = SavedSearchStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var favoritePads = FavoritePadsStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var padsCache = PadsCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State private var nav = AppNavigation.shared
    /// Highlights the Favorites section while a pad or question is dragged over it,
    /// the Finder-style cue that dropping there will pin the item.
    @State private var droppingFavorite = false
    /// The favorite row id a reorder drag is currently hovering, so an insertion line
    /// can be drawn above it (#299). Nil when no reorder drag is in flight.
    @State private var reorderTargetID: String?

    var body: some View {
        VStack(spacing: 0) {
            // A native `List(selection:)` so the section rows get the framework's
            // selection model and arrow-key navigation for free, instead of the old
            // hand-rolled VStack of buttons that had to re-add ↑/↓ via `.onMoveCommand`
            // (#281, #288). The List scrolls, so the saved-search and favorites groups
            // can still grow past the window height while the account footer stays
            // pinned below. Selection covers only the top-level sections; the Suggested
            // / Saved Searches / Favorites groups stay custom rows so their applied-
            // search highlight, drag-to-reorder, drop-to-pin, and context menus are
            // unchanged.
            List(selection: sectionSelection) {
                Section {
                    ForEach(sectionOrder, id: \.self) { value in
                        sectionRow(value)
                    }
                    // On an unlimited plan the quota page has nothing to count down, so
                    // a non-navigable "Unlimited" indicator stands in for the Quota row
                    // (#306). Untagged, so it never claims the selection.
                    if quotaIsUnlimited {
                        unlimitedQuotaRow.sidebarGroupRow()
                    }
                }

                defaultsSection
                savedSearchesSection
                favoritesSection
            }
            .listStyle(.sidebar)
            // Let the NavigationSplitView column's source-list material and the dark
            // scrim below show through, rather than the List painting its own opaque
            // background over them.
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Sections")

            Divider()
            AccountFooter()
                .padding(10)
                .background(.thinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The NavigationSplitView sidebar column already paints the vibrant source
        // list material all the way up behind the titlebar, so the traffic lights
        // sit on the sidebar like Mail without a custom NSVisualEffectView. In dark
        // mode a subtle dark scrim deepens the sidebar so it reads as distinctly
        // darker than the content pane, the way Mail's does. In light mode the App
        // Store (and Mail) keep the sidebar light — so the scrim is omitted there
        // and the native light source-list material shows through, instead of the
        // grey wash a dark scrim would leave over a light background.
        .background {
            if colorScheme == .dark {
                Color.black.opacity(0.18).ignoresSafeArea()
            }
        }
        // If the plan is revealed as unlimited while the quota page is open (e.g. the
        // restored section was Quota and the warm-up only now confirmed unlimited),
        // step away to Pads so the user isn't left on a page they can no longer reach.
        .onChange(of: quotaIsUnlimited) { _, unlimited in
            if unlimited, section == .quota { section = .pads }
        }
    }

    private var accountID: UUID? {
        accounts.currentAccountID
    }

    /// Whether the current account's plan is unlimited, read synchronously from the
    /// quota cache (warmed on session load). Only in the single-account view — the
    /// combined view spans accounts that may differ, so it keeps the normal Quota row.
    private var quotaIsUnlimited: Bool {
        guard !isMergedView, let id = accountID else { return false }
        return quotaCache.get(id)?.unlimited == true
    }

    /// The non-navigable Quota row shown on an unlimited plan: it states the plan is
    /// unlimited rather than linking to a countdown page that has nothing to count.
    private var unlimitedQuotaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "infinity")
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            // Dimmed to secondary (matching the icon) so the row reads as an
            // informational indicator rather than a tappable section — there's no
            // quota page to open on an unlimited plan (#343, #306).
            Text("Quota")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Unlimited")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
        .font(.body)
        .padding(.vertical, 7)
        .help("Your plan has unlimited pads.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota, unlimited plan")
    }

    // MARK: Saved searches

    /// One pad or question search, tagged with its list so a tap can route to the
    /// right pane and with the icon to show beside it. `id` is unique per row across
    /// both the built-in defaults and the user's saved searches.
    private struct SavedItem: Identifiable {
        let id: String
        let search: NamedSearch
        let kind: SavedSearchKind
        let icon: String
    }

    /// Both lists' saved searches, pads first, so the sidebar mirrors the section
    /// order above. The built-in defaults are surfaced separately in `defaultItems`.
    private var savedItems: [SavedItem] {
        let pads = savedSearches.searches(account: accountID, kind: .pads)
            .map { SavedItem(id: "pads-\($0.id.uuidString)", search: $0, kind: .pads, icon: "doc.text") }
        let questions = savedSearches.searches(account: accountID, kind: .questions)
            .map {
                SavedItem(
                    id: "questions-\($0.id.uuidString)",
                    search: $0,
                    kind: .questions,
                    icon: "questionmark.bubble"
                )
            }
        return pads + questions
    }

    /// The built-in pad and question searches mirrored from the chip bars,
    /// recomputed per account so "My Pads"/"My Questions" track whoever is signed
    /// in. Unlike the user's saved searches, defaults can't be deleted.
    private var defaultItems: [SavedItem] {
        let currentEmail = accounts.currentAccount?.userEmail
        let pads = DefaultSearch.padDefaults(me: currentEmail)
            .map { SavedItem(id: "default-pads-\($0.id)", search: $0.search, kind: .pads, icon: $0.icon) }
        let questions = DefaultSearch.questionDefaults(me: currentEmail)
            .map { SavedItem(id: "default-questions-\($0.id)", search: $0.search, kind: .questions, icon: $0.icon) }
        return pads + questions
    }

    // MARK: Selection

    //
    // The sidebar shows a single selection across every row, the way Mail and
    // Reminders do: tapping a suggested or saved search highlights that row and the
    // parent "Pads"/"Questions" row deselects, so the highlight always names exactly
    // what the content pane is showing. Selection is *derived* from each pane's live
    // filter signature (published into `AppNavigation`) rather than stored, so it
    // falls back to the plain top-level row the instant a filter is edited in-pane —
    // no separate invalidation step. Favorites stay plain jump-actions: selecting one
    // changes the detail, not the list's filter, so the "Questions" row stays current.

    private func appSection(for kind: SavedSearchKind) -> AppSection {
        switch kind {
        case .pads: .pads
        case .questions: .questions
        }
    }

    private func liveFilter(for kind: SavedSearchKind) -> NamedSearch {
        switch kind {
        case .pads: nav.padsFilter
        case .questions: nav.questionsFilter
        }
    }

    /// In the combined view the per-account saved searches don't apply; the sidebar
    /// instead surfaces each merged list's "Mine" preset, which it toggles and
    /// reflects through `AppNavigation`.
    private var isMergedView: Bool {
        accounts.isMergedView
    }

    private func mergedMineOnly(for kind: SavedSearchKind) -> Bool {
        switch kind {
        case .pads: nav.mergedPadsMineOnly
        case .questions: nav.mergedQuestionsMineOnly
        }
    }

    /// Whether `item` is the search currently applied in its list. True only while
    /// that list is the active section, so switching sections clears the highlight.
    private func isItemSelected(_ item: SavedItem) -> Bool {
        nav.section == appSection(for: item.kind)
            && liveFilter(for: item.kind).hasSameFilters(as: item.search)
    }

    /// Every suggested and saved row for one list kind, used to decide whether the
    /// plain top-level row should claim the selection.
    private func items(for kind: SavedSearchKind) -> [SavedItem] {
        (defaultItems + savedItems).filter { $0.kind == kind }
    }

    /// Whether a top-level row owns the selection. Pads/Questions are selected only
    /// when their list shows its plain, unfiltered contents — i.e. no suggested or
    /// saved row matches the live filter — so tapping a suggested search moves the
    /// highlight off the parent onto that row. Organization/Quota are simple toggles.
    private func isRootSelected(_ value: AppSection) -> Bool {
        switch value {
        case .pads, .questions:
            guard nav.section == value else { return false }
            let kind: SavedSearchKind = value == .pads ? .pads : .questions
            // In merged mode the only suggested row is "Mine"; the root owns the
            // selection whenever that preset is off.
            if isMergedView { return !mergedMineOnly(for: kind) }
            return !items(for: kind).contains { liveFilter(for: kind).hasSameFilters(as: $0.search) }
        case .organization, .quota:
            return nav.section == value
        }
    }

    /// The top-to-bottom order of the navigable top-level sections, shared by the
    /// rows above and the arrow-key handler so the two never disagree. Quota drops
    /// out on an unlimited plan, where its row is a non-navigable indicator (#306).
    private var sectionOrder: [AppSection] {
        quotaIsUnlimited
            ? [.pads, .questions, .organization]
            : [.pads, .questions, .organization, .quota]
    }

    /// Drives the section `List`'s selection. The getter is *derived* from each pane's
    /// live state (via `isRootSelected`) rather than stored, so it falls back to `nil`
    /// — no section highlighted — the instant a saved search is applied or a filter is
    /// edited in-pane, with no separate invalidation step. The setter routes through
    /// `selectRoot`, so a click or an arrow-key move onto Pads/Questions shows their
    /// plain list exactly as tapping the row did. `List` handles ↑/↓ navigation and the
    /// selection styling itself, replacing the old `.onMoveCommand` handler.
    private var sectionSelection: Binding<AppSection?> {
        Binding(
            get: { sectionOrder.first(where: { isRootSelected($0) }) },
            set: { newValue in
                if let newValue { selectRoot(newValue) }
            }
        )
    }

    /// A top-level section row in the `List`. Carries its `AppSection` as the selection
    /// tag and reports its label width so the column floor still fits the longest label
    /// (`SidebarRowWidthKey`). The native sidebar list paints the selection highlight, so
    /// the row is a plain `Label` rather than the old hand-painted button.
    private func sectionRow(_ value: AppSection) -> some View {
        let meta = Self.sectionMeta(value)
        return Label(meta.label, systemImage: meta.icon)
            .tag(value)
            .measuresSidebarRowWidth(meta.label)
            .accessibilityAddTraits(isRootSelected(value) ? .isSelected : [])
    }

    /// The label and SF Symbol for each navigable top-level section, in one place so the
    /// rows and any width measurement agree.
    private static func sectionMeta(_ value: AppSection) -> (label: String, icon: String) {
        switch value {
        case .pads: ("Pads", "doc.text")
        case .questions: ("Questions", "questionmark.bubble")
        case .organization: ("Organization", "building.2")
        case .quota: ("Quota", "gauge.with.dots.needle.67percent")
        }
    }

    /// Reset to the plain, unfiltered list for a top-level row, so tapping "Pads" or
    /// "Questions" clears any applied search and the highlight returns to that row.
    private func selectRoot(_ value: AppSection) {
        switch value {
        case .pads:
            if isMergedView { nav.showMergedRoot(kind: .pads) }
            else { nav.showPads(PadsRequest(applySearch: NamedSearch(name: ""))) }
        case .questions:
            if isMergedView { nav.showMergedRoot(kind: .questions) }
            else { nav.showQuestions(QuestionsRequest(applySearch: NamedSearch(name: ""))) }
        case .organization: section = value
        case .quota:
            // The quota page is unreachable on an unlimited plan (#306); the row is a
            // plain indicator there and never calls this, but guard anyway.
            if !quotaIsUnlimited { section = value }
        }
    }

    @ViewBuilder
    private var defaultsSection: some View {
        if isMergedView {
            mergedDefaultsSection
        } else {
            let items = defaultItems
            if !items.isEmpty {
                Section("Suggested") {
                    VStack(spacing: 2) {
                        ForEach(items) { item in
                            sidebarSubRow(label: item.search.name, icon: item.icon,
                                          isSelected: isItemSelected(item)) {
                                nav.applySavedSearch(item.search, kind: item.kind)
                            }
                        }
                    }
                    .sidebarGroupRow()
                }
            }
        }
    }

    /// The combined view's suggested rows: "My Pads"/"My Questions" toggle each
    /// merged list's per-account "Mine" preset (the in-list chip's sidebar twin).
    /// Tapping one switches to that list and flips the preset; the highlight tracks
    /// the live state `MergedPadsView`/`MergedQuestionsView` publish back.
    @ViewBuilder
    private var mergedDefaultsSection: some View {
        Section("Suggested") {
            VStack(spacing: 2) {
                sidebarSubRow(label: String(localized: "My Pads"), icon: "person.fill",
                              isSelected: nav.section == .pads && nav.mergedPadsMineOnly) {
                    nav.toggleMergedMine(kind: .pads)
                }
                sidebarSubRow(label: String(localized: "My Questions"), icon: "person.fill",
                              isSelected: nav.section == .questions && nav.mergedQuestionsMineOnly) {
                    nav.toggleMergedMine(kind: .questions)
                }
            }
            .sidebarGroupRow()
        }
    }

    @ViewBuilder
    private var savedSearchesSection: some View {
        let items = savedItems
        if !items.isEmpty {
            Section("Saved Searches") {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        sidebarSubRow(label: item.search.name, icon: item.icon,
                                      isSelected: isItemSelected(item)) {
                            nav.applySavedSearch(item.search, kind: item.kind)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let account = accountID {
                                    savedSearches.remove(id: item.search.id, account: account, kind: item.kind)
                                }
                            } label: {
                                Label("Delete Saved Search", systemImage: "trash")
                            }
                        }
                    }
                }
                .sidebarGroupRow()
            }
        }
    }

    // MARK: Favorites

    private struct FavoriteItem: Identifiable {
        /// Unique per row. In the merged view two accounts can both star a question
        /// with the same per-org id, so the row id namespaces by account.
        let id: String
        let questionID: Int
        /// The owning account when shown in the merged view, so a tap selects the
        /// right account's row; `nil` in a single-account view.
        let account: UUID?
        let title: String
    }

    private struct FavoritePadItem: Identifiable {
        /// Unique per row. Pad ids are globally unique, but the merged view still
        /// namespaces by account so removing a favorite targets the right account.
        let id: String
        let padID: String
        /// The owning account when shown in the merged view; `nil` single-account.
        let account: UUID?
        let title: String
    }

    /// The pinned pads to show, mirroring `favoriteItems` for questions: the current
    /// account's in a single-account view, or every mergeable account's in the
    /// combined view. Titles come from each account's pads cache, falling back to the id.
    private var favoritePadItems: [FavoritePadItem] {
        if isMergedView {
            return accounts.mergeableAccounts.flatMap { favoritePadItems(forAccount: $0.id, namespaced: true) }
        }
        guard let account = accountID else { return [] }
        return favoritePadItems(forAccount: account, namespaced: false)
    }

    private func favoritePadItems(forAccount account: UUID, namespaced: Bool) -> [FavoritePadItem] {
        let ids = favoritePads.favorites(account: account)
        guard !ids.isEmpty else { return [] }
        let titles = Dictionary(
            padsCache.get(account).map { ($0.id, $0.title.isEmpty ? $0.id : $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.map { id in
            FavoritePadItem(
                id: namespaced ? "\(account.uuidString)-\(id)" : id,
                padID: id,
                account: namespaced ? account : nil,
                title: titles[id] ?? id
            )
        }
    }

    /// The starred questions to show: the current account's in a single-account view,
    /// or every mergeable account's (in account order) in the combined "All Accounts"
    /// view, so favorites stay reachable from the sidebar there too. The title comes
    /// from the live questions cache when present (so renames show through), else the
    /// title stored with the favorite — so the name shows even before the list loads
    /// (#325), and "Question #id" is only ever a last resort for a legacy favorite
    /// whose question hasn't been seen yet.
    private var favoriteItems: [FavoriteItem] {
        if isMergedView {
            return accounts.mergeableAccounts.flatMap { favoriteItems(forAccount: $0.id, namespaced: true) }
        }
        guard let account = accountID else { return [] }
        return favoriteItems(forAccount: account, namespaced: false)
    }

    private func favoriteItems(forAccount account: UUID, namespaced: Bool) -> [FavoriteItem] {
        let favorites = favorites.titledFavorites(account: account)
        guard !favorites.isEmpty else { return [] }
        let cacheTitles = Dictionary(
            questionsCache.get(account).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        return favorites.map { favorite in
            let resolved = cacheTitles[favorite.id]
                ?? (favorite.title.isEmpty ? "Question #\(favorite.id)" : favorite.title)
            return FavoriteItem(
                id: namespaced ? "\(account.uuidString)-\(favorite.id)" : "\(favorite.id)",
                questionID: favorite.id,
                account: namespaced ? account : nil,
                title: resolved
            )
        }
    }

    /// The Favorites section is always shown, even when empty, so a pad or question
    /// row can be dragged onto it to create the first favorite (#297). Pinned pads
    /// lead, then starred questions; an empty section shows a drop hint. Dropping
    /// pins the dragged item to the account it came from (carried in the payload),
    /// which is what makes a drop in the combined view land on the right account.
    @ViewBuilder
    private var favoritesSection: some View {
        let pads = favoritePadItems
        let questions = favoriteItems
        Section("Favorites") {
            favoritesBody(pads: pads, questions: questions)
                .sidebarGroupRow()
        }
    }

    /// The Favorites group's body: the pinned-pad and starred-question rows, their
    /// empty-state hint, the drag-to-reorder insertion line, and the drop-to-pin
    /// target. Kept as one view (one `List` row) so this whole interaction — unchanged
    /// from the pre-`List` sidebar — keeps working as-is.
    private func favoritesBody(pads: [FavoritePadItem], questions: [FavoriteItem]) -> some View {
        VStack(spacing: 2) {
            ForEach(pads) { item in
                favoriteRowChrome(rowID: item.id,
                                  payload: padReorderPayload(item),
                                  onReorder: { reorderPad($0, before: item) }) {
                    sidebarSubRow(label: item.title, icon: "star.fill", iconTint: .yellow) {
                        if item.account != nil {
                            section = .pads
                            MergedRouting.shared.selectFavoritePad(id: item.padID)
                        } else {
                            nav.showFavoritePad(id: item.padID)
                        }
                    }
                    .contextMenu { removeFavoriteButton { unfavoritePad(item) } }
                }
            }
            ForEach(questions) { item in
                favoriteRowChrome(rowID: item.id,
                                  payload: questionReorderPayload(item),
                                  onReorder: { reorderQuestion($0, before: item) }) {
                    sidebarSubRow(label: item.title, icon: "star.fill", iconTint: .yellow) {
                        if let account = item.account {
                            // Merged view: switch to the combined questions list and let
                            // it select the right account's row (per-org ids collide, so
                            // the account must travel with the id).
                            section = .questions
                            MergedRouting.shared.selectFavoriteQuestion(account: account, id: item.questionID)
                        } else {
                            nav.showFavoriteQuestion(id: item.questionID)
                        }
                    }
                    .contextMenu { removeFavoriteButton { unfavoriteQuestion(item) } }
                }
            }
            if pads.isEmpty, questions.isEmpty {
                Text("Drag pads or questions here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
            }
        }
        // Fill the section's full width and make the whole rectangle — including the
        // gaps between rows and the empty space below them — one hit-testable drop
        // target, so a drop lands anywhere over Favorites rather than only on the
        // exact bounds of a row or the hint text.
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
            droppingFavorite ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        // `.onDrop` (NSItemProvider-based) rather than `.dropDestination(for:)`: inside
        // a `List` row the latter highlights on hover but never fires its action on
        // release (#346), so the drop silently fails. `.onDrop` delivers the providers
        // reliably here. This container target catches drops over the gaps between rows
        // and the empty space below them; each favorite row carries its own target too
        // (see `favoriteRowChrome`), since a row's drop region would otherwise occlude
        // this one and leave the rows themselves as dead spots.
        .onDrop(of: [.coderpadFavorite], isTargeted: $droppingFavorite) { providers in
            for provider in providers { loadFavoriteAdd(from: provider) }
            return true
        }
    }

    /// Decodes a dragged-in `FavoriteDrop` from a provider and pins it. Shared by the
    /// section container and each favorite row's drop target so the whole Favorites
    /// area accepts an add-a-favorite drop.
    private func loadFavoriteAdd(from provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavorite.identifier) { data, _ in
            guard let data, let drop = try? JSONDecoder().decode(FavoriteDrop.self, from: data) else { return }
            Task { @MainActor in _ = handleFavoriteDrop([drop]) }
        }
    }

    /// Decodes a within-sidebar `FavoriteReorder` from a provider and applies the move.
    private func loadFavoriteReorder(from provider: NSItemProvider, onReorder: @escaping @MainActor (FavoriteReorder) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavoriteReorder.identifier) { data, _ in
            guard let data, let reorder = try? JSONDecoder().decode(FavoriteReorder.self, from: data) else { return }
            Task { @MainActor in onReorder(reorder) }
        }
    }

    private func removeFavoriteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label("Remove from Favorites", systemImage: "star.slash")
        }
    }

    private func unfavoritePad(_ item: FavoritePadItem) {
        guard let account = item.account ?? accountID else { return }
        favoritePads.remove(item.padID, account: account)
    }

    private func unfavoriteQuestion(_ item: FavoriteItem) {
        guard let account = item.account ?? accountID else { return }
        favorites.toggle(item.questionID, title: item.title, account: account)
    }

    /// Pins each dropped pad or question to the account carried in its payload (the
    /// originating account, so a drop in the combined view lands on the right one).
    /// Returns whether anything was accepted, which drives the drop animation.
    private func handleFavoriteDrop(_ drops: [FavoriteDrop]) -> Bool {
        var accepted = false
        for drop in drops {
            switch drop {
            case let .pad(account, id, _):
                favoritePads.add(id, account: account)
                accepted = true
            case let .question(account, id, title):
                favorites.add(id, title: title, account: account)
                accepted = true
            }
        }
        return accepted
    }

    /// Wraps a favorite row so it can be dragged to reorder (#299): it carries a
    /// `FavoriteReorder` payload, draws a Finder-style insertion line above itself
    /// while a drag hovers, and reorders on drop. The row's own drop target accepts
    /// both a within-sidebar reorder *and* an add-a-favorite drag from a list — without
    /// the latter, the row would occlude the section's add target and leave each row a
    /// dead spot where a question or pad couldn't be dropped (#346).
    @ViewBuilder
    private func favoriteRowChrome(
        rowID: String,
        payload: FavoriteReorder?,
        onReorder: @escaping @MainActor (FavoriteReorder) -> Void,
        @ViewBuilder row: () -> some View
    ) -> some View {
        let decorated = row()
            .overlay(alignment: .top) {
                if reorderTargetID == rowID {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
            // `.onDrop` rather than `.dropDestination(for:)` for the same reason as the
            // section target: the latter never fires its action inside a `List` row.
            .onDrop(of: [.coderpadFavoriteReorder, .coderpadFavorite], isTargeted: Binding(
                get: { reorderTargetID == rowID },
                set: { targeted in
                    reorderTargetID = targeted ? rowID : (reorderTargetID == rowID ? nil : reorderTargetID)
                }
            )) { providers in
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.coderpadFavoriteReorder.identifier) {
                        loadFavoriteReorder(from: provider) { reorder in
                            reorderTargetID = nil
                            onReorder(reorder)
                        }
                    } else {
                        loadFavoriteAdd(from: provider)
                    }
                }
                return true
            }
        // Only rows whose owning account is known can be dragged to reorder.
        if let payload {
            decorated.draggable(payload)
        } else {
            decorated
        }
    }

    private func padReorderPayload(_ item: FavoritePadItem) -> FavoriteReorder? {
        guard let account = item.account ?? accountID else { return nil }
        return .pad(account: account, id: item.padID)
    }

    private func questionReorderPayload(_ item: FavoriteItem) -> FavoriteReorder? {
        guard let account = item.account ?? accountID else { return nil }
        return .question(account: account, id: item.questionID)
    }

    /// Reorders a dropped pad favorite to sit before `item`, but only within the
    /// same account (a reorder never moves a favorite between accounts).
    private func reorderPad(_ dropped: FavoriteReorder, before item: FavoritePadItem) {
        guard case let .pad(account, id) = dropped,
              let targetAccount = item.account ?? accountID,
              account == targetAccount else { return }
        favoritePads.move(id, before: item.padID, account: account)
    }

    private func reorderQuestion(_ dropped: FavoriteReorder, before item: FavoriteItem) {
        guard case let .question(account, id) = dropped,
              let targetAccount = item.account ?? accountID,
              account == targetAccount else { return }
        favorites.move(id, before: item.questionID, account: account)
    }

    // MARK: Row chrome

    /// A search-recall row for the Suggested / Saved Searches / Favorites groups. Unlike
    /// the top-level section rows (which the `List` selects and styles natively), these
    /// stay custom buttons so they can paint the applied-search highlight, carry context
    /// menus, and be dragged — and they don't feed `SidebarRowWidthKey`, so long names
    /// truncate instead of widening the column. `isSelected` marks the row whose search
    /// is currently applied, so the sidebar shows one honest "you are here" across groups.
    private func sidebarSubRow(label: String, icon: String, iconTint: Color = .secondary,
                               isSelected: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(isSelected ? Color.accentColor : iconTint)
                    .frame(width: 22)
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
            }
            // No leading inset of its own: the row sits at the List's standard sidebar
            // margin (which `sidebarGroupRow` falls back to), so a suggested/saved/favorite
            // icon lines up with the top-level "Pads"/"Questions" row icons above instead
            // of reading as an indented child of them (#345). The full-width `Spacer` still
            // lets the selection highlight span the row, inset by that same margin.
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    /// Renders a custom sidebar group (Suggested / Saved Searches / Favorites) as a
    /// single, full-width `List` row: clears the framework's row insets, background, and
    /// separator so the group's own padding and highlights show through unchanged, and so
    /// these rows never pick up the native selection chrome reserved for the section rows.
    func sidebarGroupRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
