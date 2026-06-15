//
//  ContentView+Sidebar.swift
//  coderpad
//

import SwiftUI

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
            // Scrolls so the saved-search and favorites lists can grow past the
            // window height while the account footer stays pinned to the bottom.
            ScrollView {
                VStack(spacing: 2) {
                    sidebarRow(.pads, "Pads", "doc.text")
                    sidebarRow(.questions, "Questions", "questionmark.bubble")
                    sidebarRow(.organization, "Organization", "building.2")
                    // On an unlimited plan the quota page has nothing to count down, so
                    // the row becomes a non-navigable "Unlimited" indicator instead (#306).
                    if quotaIsUnlimited {
                        unlimitedQuotaRow
                    } else {
                        sidebarRow(.quota, "Quota", "gauge.with.dots.needle.67percent")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                // The hand-rolled rows (a plain VStack of buttons, kept so the
                // Mail-style highlight can be painted) lost the arrow-key navigation
                // a `List` gives for free. Make the section group focusable and step
                // through it on ↑/↓ so the keyboard can move between the four sections
                // again. `focusEffectDisabled` suppresses the default group focus
                // ring (an ugly blue box drawn around all four rows); the selected
                // row's own highlight is the "you are here" cue, so the ring is
                // redundant as well as unsightly.
                .focusable()
                .focusEffectDisabled()
                .onMoveCommand(perform: moveSection)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sections")

                defaultsSection
                savedSearchesSection
                favoritesSection
            }
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
            Text("Quota")
                .foregroundStyle(.primary)
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
        .padding(.horizontal, 8)
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

    /// Step the selected section on ↑/↓ when the section group has keyboard focus.
    /// Clamps at the ends rather than wrapping, the way a source list does, and routes
    /// through `selectRoot` so moving onto Pads/Questions shows their plain list (the
    /// same as clicking the row). Left/right are ignored.
    private func moveSection(_ direction: MoveCommandDirection) {
        let order = sectionOrder
        guard let current = order.firstIndex(of: nav.section) else {
            // The active section isn't one of the four (a saved search is applied):
            // ↑/↓ re-enters the list at its current section's plain row.
            selectRoot(nav.section == .questions ? .questions : .pads)
            return
        }
        let next: Int
        switch direction {
        case .up: next = current - 1
        case .down: next = current + 1
        default: return
        }
        guard order.indices.contains(next) else { return }
        selectRoot(order[next])
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
                sidebarSectionHeader("Suggested")
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        sidebarSubRow(label: item.search.name, icon: item.icon,
                                      isSelected: isItemSelected(item)) {
                            nav.applySavedSearch(item.search, kind: item.kind)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// The combined view's suggested rows: "My Pads"/"My Questions" toggle each
    /// merged list's per-account "Mine" preset (the in-list chip's sidebar twin).
    /// Tapping one switches to that list and flips the preset; the highlight tracks
    /// the live state `MergedPadsView`/`MergedQuestionsView` publish back.
    @ViewBuilder
    private var mergedDefaultsSection: some View {
        sidebarSectionHeader("Suggested")
        VStack(spacing: 2) {
            sidebarSubRow(label: "My Pads", icon: "person.fill",
                          isSelected: nav.section == .pads && nav.mergedPadsMineOnly) {
                nav.toggleMergedMine(kind: .pads)
            }
            sidebarSubRow(label: "My Questions", icon: "person.fill",
                          isSelected: nav.section == .questions && nav.mergedQuestionsMineOnly) {
                nav.toggleMergedMine(kind: .questions)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var savedSearchesSection: some View {
        let items = savedItems
        if !items.isEmpty {
            sidebarSectionHeader("Saved Searches")
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
            .padding(.horizontal, 8)
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
        sidebarSectionHeader("Favorites")
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
        .padding(.horizontal, 8)
        .background(
            droppingFavorite ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .dropDestination(for: FavoriteDrop.self) { drops, _ in
            handleFavoriteDrop(drops)
        } isTargeted: { droppingFavorite = $0 }
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
    /// while a reorder drag hovers, and reorders on drop. The reorder type is
    /// distinct from the add-a-favorite `FavoriteDrop`, so a row's own drop target
    /// only ever reacts to a reorder, never to a row dragged in from a list.
    @ViewBuilder
    private func favoriteRowChrome(
        rowID: String,
        payload: FavoriteReorder?,
        onReorder: @escaping (FavoriteReorder) -> Void,
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
            .dropDestination(for: FavoriteReorder.self) { items, _ in
                reorderTargetID = nil
                guard let first = items.first else { return false }
                onReorder(first)
                return true
            } isTargeted: { targeted in
                reorderTargetID = targeted ? rowID : (reorderTargetID == rowID ? nil : reorderTargetID)
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

    private func sidebarSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    /// A lighter row than `sidebarRow`: a search-recall row that doesn't feed
    /// `SidebarRowWidthKey`, so long names truncate instead of widening the column.
    /// It carries the same single-selection highlight as the top-level rows when its
    /// search is the one currently applied (`isSelected`), so the sidebar shows one
    /// honest "you are here" across every row.
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
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                isSelected ? Color.primary.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sidebarRow(_ value: AppSection, _ label: String, _ icon: String) -> some View {
        let isSelected = isRootSelected(value)
        Button {
            selectRoot(value)
        } label: {
            HStack(spacing: 8) {
                // Mail dims unselected icons to secondary and tints both icon and
                // label with the accent on the selected row; the label stays primary
                // white when unselected.
                Image(systemName: icon)
                    .imageScale(.large)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
            }
            // Matches the App Store sidebar's metrics: the system `.body` row font,
            // larger icons, and a touch more row height than the previous `.callout`.
            .font(.body)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                isSelected
                    ? Color.primary.opacity(0.10)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .measuresSidebarRowWidth(label)
    }
}
