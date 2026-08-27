//
//  ContentView+SidebarSections.swift
//  coderpad
//

import SwiftUI

struct SidebarSavedItem: Identifiable {
    let id: String
    let search: NamedSearch
    let kind: SavedSearchKind
    let icon: String
    var suggestionID: String?
}

final class SidebarDefaultItemsProvider {
    private var cachedEmail: String?
    private var cachedItems: [SidebarSavedItem] = []
    private var hasCachedItems = false

    func items(currentEmail: String?) -> [SidebarSavedItem] {
        guard !hasCachedItems || currentEmail != cachedEmail else { return cachedItems }

        let pads = DefaultSearch.padDefaults(me: currentEmail)
            .map { SidebarSavedItem(id: "default-pads-\($0.id)", search: $0.search, kind: .pads,
                                    icon: $0.icon, suggestionID: $0.id) }
        let questions = DefaultSearch.questionDefaults(me: currentEmail)
            .map {
                SidebarSavedItem(id: "default-questions-\($0.id)",
                                 search: $0.search,
                                 kind: .questions,
                                 icon: $0.icon,
                                 suggestionID: $0.id)
            }
        cachedEmail = currentEmail
        cachedItems = pads + questions
        hasCachedItems = true
        return cachedItems
    }
}

extension Sidebar {
    // MARK: Suggested searches

    /// The built-in pad and question searches mirrored from the chip bars,
    /// recomputed only when "My Pads"/"My Questions" need a different account email.
    private var defaultItems: [SidebarSavedItem] {
        defaultItemsProvider.items(currentEmail: accounts.currentAccount?.userEmail)
    }

    // MARK: Selection

    //
    // The sidebar keeps a single selection on the active top-level row, the way Mail
    // and Reminders do. The "Pads"/"Questions" row stays highlighted for as long as
    // its list is the active section. Suggested searches are momentary actions rather
    // than a selection: tapping one applies its filter but never highlights the row,
    // and the parent row keeps the highlight so the selection never vanishes. Favorites
    // stay plain jump-actions too: selecting one changes the detail, not the list's
    // filter, so the "Questions" row stays current. Selection is *derived* from the
    // active section (published into `AppNavigation`) rather than stored.

    /// In the combined view the per-account Suggested searches don't apply; the
    /// sidebar instead surfaces each merged list's "Mine" preset, which it toggles
    /// and reflects through `AppNavigation`.
    var isMergedView: Bool {
        accounts.isMergedView
    }

    /// Whether a top-level row owns the selection. Each row stays highlighted for as
    /// long as it is the active section — including while a suggested search (or, in
    /// merged mode, a "Mine"/"Active" preset) is applied, since those are momentary
    /// actions rather than a selection. The highlight always names the active pane
    /// instead of vanishing onto a suggested row.
    func isRootSelected(_ value: AppSection) -> Bool {
        section == value
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
    /// — no section highlighted — the instant a suggested search is applied or a filter
    /// is edited in-pane, with no separate invalidation step. The setter routes through
    /// `selectRoot`, so a click or an arrow-key move onto Pads/Questions shows their
    /// plain list exactly as tapping the row did. `List` handles ↑/↓ navigation and the
    /// selection styling itself, replacing the old `.onMoveCommand` handler.
    ///
    /// Takes the navigable order rather than recomputing it: `body` already bound it
    /// once for the rows and the list identity, and rebuilding it inside the getter
    /// made a third pass over the accounts per render (#2109). The binding is rebuilt
    /// with the rest of the `List` configuration whenever that order changes, so the
    /// captured value can't outlive the pass it belongs to.
    func sectionSelection(in order: [AppSection]) -> Binding<AppSection?> {
        Binding(
            get: { order.first(where: { isRootSelected($0) }) },
            set: { newValue in
                if let newValue {
                    selectRoot(newValue)
                }
            }
        )
    }

    /// A top-level section row in the `List`. Reports its label width so the column
    /// floor still fits the longest label (`SidebarRowWidthKey`). On macOS the root rows
    /// paint their own stable selection, because the native source-list highlight flips
    /// from emphasized blue to inactive grey when focus moves into the selected pane.
    @ViewBuilder
    func sectionRow(_ value: AppSection) -> some View {
        #if os(visionOS)
            visionSectionRow(value)
        #elseif os(macOS)
            let isSelected = isRootSelected(value)
            Button { selectRoot(value) } label: {
                HStack(spacing: 10) {
                    Image(systemName: value.systemImage)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .accessibilityHidden(true)
                        .frame(width: 24)
                    Text(value.label)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                }
                .appStoreSidebarRowInsets()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? Color.primary.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(inactiveDimming)
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            .measuresSidebarRowWidth(LocalizedStringKey(value.label))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #else
            if PlatformIdiom.usesVisionInterface {
                visionSectionRow(value)
            } else {
                Label(value.label, systemImage: value.systemImage)
                    .tag(value)
                    .listItemTint(.monochrome)
                    .measuresSidebarRowWidth(LocalizedStringKey(value.label))
                    .accessibilityAddTraits(isRootSelected(value) ? .isSelected : [])
            }
        #endif
    }

    private func visionSectionRow(_ value: AppSection) -> some View {
        let isSelected = isRootSelected(value)

        return Button { selectRoot(value) } label: {
            HStack(spacing: 8) {
                Image(systemName: value.systemImage)
                    .imageScale(.large)
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.78))
                    .accessibilityHidden(true)
                    .frame(width: 22)
                Text(value.label)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.72) : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .selectionDisabled()
        .visionListRowHoverLift()
        .measuresSidebarRowWidth(LocalizedStringKey(value.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    #if os(macOS)
        /// Replaces the native `List(selection:)` arrow handling for the custom macOS root
        /// rows, keeping Next/Previous section movement on the real top-level destinations.
        func moveSectionSelection(_ direction: MoveCommandDirection) {
            let delta: Int
            switch direction {
            case .up: delta = -1
            case .down: delta = 1
            default: return
            }

            let order = sectionOrder
            guard !order.isEmpty else { return }

            let currentIndex = order.firstIndex(of: section) ?? 0
            let nextIndex = (currentIndex + delta + order.count) % order.count
            selectRoot(order[nextIndex])
        }
    #endif

    /// Reset to the plain, unfiltered list for a top-level row, so tapping "Pads" or
    /// "Questions" clears any applied search and the highlight returns to that row.
    func selectRoot(_ value: AppSection) {
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
            if !quotaIsUnlimited {
                section = value
            }

        case .screen:
            // Only reachable when the account has a Screen key (the row is gated on
            // `screenSectionAvailable`), but guard anyway.
            if screenSectionAvailable {
                section = value
            }
        }
    }

    @ViewBuilder
    var defaultsSection: some View {
        if isMergedView {
            mergedDefaultsSection
        } else {
            let items = defaultItems
            if !items.isEmpty {
                Section("Smart Lists") {
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
                            // Suggested searches are momentary actions, not a sticky
                            // selection: clicking one applies its filter but never leaves
                            // the row highlighted. The parent Pads/Questions row also
                            // deselects while a suggested filter is applied (see
                            // `isRootSelected`), so nothing in the sidebar stays lit.
                            sidebarSubRow(label: item.search.name, icon: item.icon) {
                                nav.applySuggestedSearch(item.search, kind: item.kind)
                            }
                            .contextMenu {
                                if let suggestionID = item.suggestionID,
                                   let account = accounts.currentAccountID {
                                    Button("Hide Suggestion") {
                                        suggestionPreferences.dismiss(suggestionID, kind: item.kind, account: account)
                                        defaultItemsProvider = SidebarDefaultItemsProvider()
                                    }
                                }
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
    /// Tapping one switches to that list and flips the preset. Like the per-account
    /// suggested searches these are momentary actions, not a selection, so the rows
    /// never highlight — the parent "Pads"/"Questions" row keeps the selection.
    private var mergedDefaultsSection: some View {
        Section("Smart Lists") {
            VStack(spacing: 2) {
                // Capture `nav`/`windowNav` (not `self`) in the row tap closures — see the
                // note in `defaultsSection`: capturing the whole `Sidebar` struct faults in
                // `swift_retain` while SwiftUI copies the row value on the iPad layout path.
                let nav = nav
                let windowNav = windowNav
                sidebarSubRow(label: String(localized: "My Pads"), icon: "person.fill") {
                    nav.toggleMergedMine(kind: .pads, currentlyOn: windowNav.mergedPadsMineOnly)
                }
                sidebarSubRow(label: String(localized: "Active Pads"), icon: "bolt.fill") {
                    nav.toggleMergedPadsActive(currentlyOn: windowNav.mergedPadsActiveOnly)
                }
                sidebarSubRow(label: String(localized: "My Questions"), icon: "person.fill.questionmark") {
                    nav.toggleMergedMine(kind: .questions, currentlyOn: windowNav.mergedQuestionsMineOnly)
                }
            }
            .sidebarGroupRow()
        }
    }
}

extension View {
    /// Uses the spacious App Store-style row geometry on macOS while preserving the
    /// platform-native compact inset used by iPad and vision sidebars.
    func appStoreSidebarRowInsets() -> some View {
        #if os(macOS)
            padding(.vertical, 9)
                .padding(.horizontal, 10)
        #else
            padding(.vertical, 5)
        #endif
    }
}
