//
//  ContentView+SidebarSections.swift
//  coderpad
//

import SwiftUI

extension Sidebar {
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
    var isMergedView: Bool {
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

        case .organization, .quota, .screen:
            return nav.section == value
        }
    }

    /// The top-to-bottom order of the navigable top-level sections, shared by the
    /// sidebar rows, the arrow-key handler, and the Go ▸ Next/Previous Section
    /// commands so they never disagree (#481). Delegates to `AppSection.navigable`,
    /// the single source of truth (Quota drops out on an unlimited plan #306; Screen
    /// appears only with a Screen key #432). Reads the shared account/quota stores —
    /// the same @Observable instances this view holds — so it still invalidates the
    /// sidebar when availability changes.
    var sectionOrder: [AppSection] {
        AppSection.navigable
    }

    /// Drives the section `List`'s selection. The getter is *derived* from each pane's
    /// live state (via `isRootSelected`) rather than stored, so it falls back to `nil`
    /// — no section highlighted — the instant a saved search is applied or a filter is
    /// edited in-pane, with no separate invalidation step. The setter routes through
    /// `selectRoot`, so a click or an arrow-key move onto Pads/Questions shows their
    /// plain list exactly as tapping the row did. `List` handles ↑/↓ navigation and the
    /// selection styling itself, replacing the old `.onMoveCommand` handler.
    var sectionSelection: Binding<AppSection?> {
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
    func sectionRow(_ value: AppSection) -> some View {
        let meta = Self.sectionMeta(value)
        // Plain native sidebar `Label` — a subtle monochrome glyph, the standard
        // source-list look — rather than the tinted icon tile that read as too
        // jazzy (#398, reverting #352's tile experiment).
        return Label(meta.label, systemImage: meta.icon)
            .tag(value)
            .measuresSidebarRowWidth(meta.label)
            .accessibilityAddTraits(isRootSelected(value) ? .isSelected : [])
    }

    /// The label and SF Symbol for each navigable top-level section, in one place so the
    /// rows and any width measurement agree.
    private static func sectionMeta(_ value: AppSection) -> (label: LocalizedStringKey, icon: String) {
        switch value {
        case .pads: ("Pads", "doc.text")
        case .questions: ("Questions", "questionmark.bubble")
        case .organization: ("Organization", "building.2")
        case .quota: ("Quota", "gauge.with.dots.needle.67percent")
        case .screen: ("Screen", "person.crop.rectangle.stack")
        }
    }

    /// Reset to the plain, unfiltered list for a top-level row, so tapping "Pads" or
    /// "Questions" clears any applied search and the highlight returns to that row.
    private func selectRoot(_ value: AppSection) {
        switch value {
        case .pads:
            if isMergedView {
                nav.showMergedRoot(kind: .pads)
            } else {
                nav.showPads(PadsRequest(applySearch: NamedSearch(name: "")))
            }

        case .questions:
            if isMergedView {
                nav.showMergedRoot(kind: .questions)
            } else {
                nav.showQuestions(QuestionsRequest(applySearch: NamedSearch(name: "")))
            }

        case .organization: section = value

        case .quota:
            // The quota page is unreachable on an unlimited plan (#306); the row is a
            // plain indicator there and never calls this, but guard anyway.
            if !quotaIsUnlimited { section = value }

        case .screen:
            // Only reachable when the account has a Screen key (the row is gated on
            // `screenSectionAvailable`), but guard anyway.
            if screenSectionAvailable { section = value }
        }
    }

    @ViewBuilder
    var defaultsSection: some View {
        if isMergedView {
            mergedDefaultsSection
        } else {
            let items = defaultItems
            if !items.isEmpty {
                Section("Suggested") {
                    VStack(spacing: 2) {
                        ForEach(items) { item in
                            // Bind `nav` to a local so the row's tap closure captures
                            // only the `AppNavigation` reference and the value-type
                            // `item`, not `self`. Capturing the whole `Sidebar` struct
                            // (with its `@State`/`@Binding` storage) makes SwiftUI fault
                            // in `swift_retain` while copying the row value on the iPad
                            // `NavigationSplitView` layout path (EXC_BAD_ACCESS on first
                            // layout, so the app shows only a black screen).
                            let nav = nav
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
    private var mergedDefaultsSection: some View {
        Section("Suggested") {
            VStack(spacing: 2) {
                // Capture `nav` (not `self`) in the row tap closures — see the note in
                // `defaultsSection`: capturing the whole `Sidebar` struct faults in
                // `swift_retain` while SwiftUI copies the row value on the iPad layout path.
                let nav = nav
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
    var savedSearchesSection: some View {
        let items = savedItems
        if !items.isEmpty {
            Section("Saved Searches") {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        // Capture the stores (not `self`) in the row's tap and delete
                        // closures — see the note in `defaultsSection`: capturing the
                        // whole `Sidebar` struct faults in `swift_retain` while SwiftUI
                        // copies the row value on the iPad layout path.
                        let nav = nav
                        let savedSearches = savedSearches
                        let accountID = accountID
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
}
