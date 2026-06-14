//
//  ContentView+Sidebar.swift
//  coderpad
//

import SwiftUI

struct Sidebar: View {
    @Binding var section: AppSection
    @State private var accounts = AccountsStore.shared
    @State private var savedSearches = SavedSearchStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var nav = AppNavigation.shared

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls so the saved-search and favorites lists can grow past the
            // window height while the account footer stays pinned to the bottom.
            ScrollView {
                VStack(spacing: 2) {
                    sidebarRow(.pads, "Pads", "doc.text")
                    sidebarRow(.questions, "Questions", "questionmark.bubble")
                    sidebarRow(.organization, "Organization", "building.2")
                    sidebarRow(.quota, "Quota", "gauge.with.dots.needle.67percent")
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
        // sit on the sidebar like Mail without a custom NSVisualEffectView. A subtle
        // dark scrim over it deepens the sidebar so it reads as distinctly darker
        // than the content pane, the way Mail's does, while still letting the
        // translucency show through.
        .background {
            Color.black.opacity(0.18).ignoresSafeArea()
        }
    }

    private var accountID: UUID? {
        accounts.currentAccountID
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

    /// The fixed top-to-bottom order of the four top-level sections, shared by the
    /// rows above and the arrow-key handler so the two never disagree.
    private static let sectionOrder: [AppSection] = [.pads, .questions, .organization, .quota]

    /// Step the selected section on ↑/↓ when the section group has keyboard focus.
    /// Clamps at the ends rather than wrapping, the way a source list does, and routes
    /// through `selectRoot` so moving onto Pads/Questions shows their plain list (the
    /// same as clicking the row). Left/right are ignored.
    private func moveSection(_ direction: MoveCommandDirection) {
        let order = Self.sectionOrder
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
        case .organization, .quota: section = value
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
        let id: Int
        let title: String
    }

    /// The current account's starred questions, in the order they were starred.
    /// Titles come from the questions cache (warmed on launch and persisted), so
    /// they're available even before the Questions pane has been opened; a favorite
    /// whose question isn't cached yet falls back to its id.
    private var favoriteItems: [FavoriteItem] {
        guard let account = accountID else { return [] }
        let ids = favorites.favorites(account: account)
        guard !ids.isEmpty else { return [] }
        let titles = Dictionary(
            questionsCache.get(account).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.map { FavoriteItem(id: $0, title: titles[$0] ?? "Question #\($0)") }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let items = favoriteItems
        if !items.isEmpty {
            sidebarSectionHeader("Favorites")
            VStack(spacing: 2) {
                ForEach(items) { item in
                    sidebarSubRow(label: item.title, icon: "star.fill", iconTint: .yellow) {
                        nav.showFavoriteQuestion(id: item.id)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
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
