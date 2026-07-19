//
//  ContentView+Sidebar.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Binding var section: AppSection
    @Environment(\.colorScheme) private var colorScheme
    /// Snap the favourites drop spacer instead of sliding it when Reduce Motion is on (#614).
    /// Not `private`: read from the `favoriteDropSpacer` in the sidebar-favourites extension.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.undoManager) var undoManager
    // Native sidebar rows desaturate when their window stops being the active one;
    // the custom unlimited-quota row has to read this state to dim in step (#347).
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #endif
    @State var accounts = AccountsStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var favoritePads = FavoritePadsStore.shared
    @State var favoritesOrder = FavoritesOrderStore.shared
    @State var questionsCache = QuestionsCacheStore.shared
    @State var padsCache = PadsCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    /// Pending "this section became unavailable" moves, held so a dip that resolves
    /// within the grace window cancels them (#2247, #2252).
    @State private var leaveQuotaTask: Task<Void, Never>?
    @State private var leaveScreenTask: Task<Void, Never>?
    @State var nav = AppNavigation.shared
    @State var defaultItemsProvider = SidebarDefaultItemsProvider()
    /// This window's published navigation state (injected by `ContentView`), read so
    /// the merged "Mine"/"Active" toggles aim at what *this* window's lists show
    /// rather than whichever window published last (#909).
    @Environment(WindowNavigation.self) var windowNav
    /// Highlights the Favorites section while an item is dragged over it, the
    /// Finder-style cue that dropping there will pin the item.
    @State var droppingFavorites = false
    /// Drives the empty-Favourites drop zone to appear only while a favorite drag is in
    /// flight, so an empty section keeps no resting gap (#444).
    @State var favoriteDragMonitor = FavoriteDragMonitor.shared
    /// Which window this sidebar is in, so it reveals its empty-Favorites drop zone
    /// only for a drag started here (#2514).
    @Environment(\.windowScope) var windowScope
    /// Whether the Favorites sidebar section is expanded. Kept as view state so the
    /// collapsed/expanded choice follows the current sidebar instance.
    @State var favoritesSectionExpanded = true
    /// The favorite row id a reorder drag is currently hovering, so an insertion line
    /// can be drawn above it (#299). Nil when no reorder drag is in flight.
    @State var reorderTargetID: String?
    /// Memo of the Favorites section's rows, refreshed by `favoritesSection` when the
    /// favourites, their order, or the caches behind their titles change (#2107).
    @State var favoriteEntriesCache = FavoriteEntriesCache()

    var body: some View {
        // Availability is asked for repeatedly across one body pass — the rows, the
        // selection binding, the list identity, and the two "section went away"
        // handlers all want it — and each ask walks the accounts and the quota cache
        // to rebuild the navigable order (#2109). Bind it once here and hand the same
        // values around; the reads still happen inside `body`, so the view keeps
        // invalidating when availability changes.
        let order = sectionOrder
        let unlimitedQuota = quotaIsUnlimited
        let screenAvailable = screenSectionAvailable
        return VStack(spacing: 0) {
            // A native `List(selection:)` so the section rows get the framework's
            // selection model and arrow-key navigation for free, instead of the old
            // hand-rolled VStack of buttons that had to re-add ↑/↓ via `.onMoveCommand`
            // (#281, #288). The List scrolls, so the Suggested and Favorites groups
            // can still grow past the window height while the account footer stays
            // pinned below. Selection covers only the top-level sections; the Suggested
            // / Favorites groups stay custom rows so their applied-search highlight,
            // drag-to-reorder, drop-to-pin, and context menus are unchanged.
            List(selection: sectionSelection(in: order)) {
                Section {
                    ForEach(order, id: \.self) { value in
                        sectionRow(value)
                    }
                    // On an unlimited plan the quota page has nothing to count down, so
                    // a non-navigable "Unlimited" indicator stands in for the Quota row
                    // (#306). Untagged, so it never claims the selection.
                    if unlimitedQuota {
                        #if os(macOS)
                            // Keep the DEFAULT row insets and add the same internal
                            // horizontal padding as `sectionRow`, so the infinity icon
                            // lines up with the section icons above — the zeroed-inset
                            // group treatment left this row further left than every
                            // other section row (#1048).
                            unlimitedQuotaRow
                                .padding(.horizontal, 6)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .selectionDisabled()
                        #else
                            unlimitedQuotaRow.sidebarGroupRow()
                        #endif
                    }
                }

                defaultsSection
                favoritesSection
            }
            .listStyle(.sidebar)
            // Let the NavigationSplitView column's source-list material and the dark
            // scrim below show through, rather than the List painting its own opaque
            // background over them.
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Sections")
            .id(sidebarListIdentity(order: order,
                                    unlimitedQuota: unlimitedQuota,
                                    screenAvailable: screenAvailable))
            #if os(macOS)
                .onMoveCommand(perform: moveSectionSelection)
            #endif

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
        // Settled first: see `SectionAvailabilitySettling` (#2247).
        .onChange(of: unlimitedQuota) { _, unlimited in
            guard unlimited, section == .quota else {
                leaveQuotaTask?.cancel()
                leaveQuotaTask = nil
                return
            }

            leaveQuotaTask?.cancel()
            leaveQuotaTask = Task { @MainActor in
                try? await Task.sleep(for: SectionAvailabilitySettling.grace)
                guard !Task.isCancelled, quotaIsUnlimited, section == .quota else { return }

                section = .pads
            }
        }
        // If the Screen section becomes unreachable (key removed, or switching to the
        // combined view), step away to Pads so the user isn't left on a gone section.
        // Settled first, so a transient keychain dip during an account refresh doesn't
        // destroy the user's Screen context (#2252).
        .onChange(of: screenAvailable) { _, available in
            guard !available, section == .screen else {
                leaveScreenTask?.cancel()
                leaveScreenTask = nil
                return
            }

            leaveScreenTask?.cancel()
            leaveScreenTask = Task { @MainActor in
                try? await Task.sleep(for: SectionAvailabilitySettling.grace)
                guard !Task.isCancelled, !screenSectionAvailable, section == .screen else { return }

                section = .pads
            }
        }
        .onDisappear {
            leaveQuotaTask?.cancel()
            leaveScreenTask?.cancel()
            leaveQuotaTask = nil
            leaveScreenTask = nil
        }
    }

    var accountID: UUID? {
        accounts.currentAccountID
    }

    /// The first native `List` section changes shape when Quota/Screen availability
    /// changes. Rebuilding the source list for those structural changes avoids an
    /// AppKit diff assertion where the section reports the new count without matching
    /// insert/delete bookkeeping.
    private func sidebarListIdentity(order: [AppSection],
                                     unlimitedQuota: Bool,
                                     screenAvailable: Bool) -> String {
        let rootRows = order.map(\.rawValue).joined(separator: "|")
        return [
            rootRows,
            unlimitedQuota ? "quota-unlimited" : "quota-navigable",
            screenAvailable ? "screen" : "no-screen"
        ].joined(separator: ":")
    }

    /// The framework dims native sidebar rows when the window stops being the active
    /// one; the hand-built rows mirror that by reading `controlActiveState`. That env
    /// value is macOS-only, so on iOS (no active/inactive window state) there's no
    /// inactive dimming and the rows stay at full opacity.
    var inactiveDimming: Double {
        #if os(macOS)
            controlActiveState == .inactive ? 0.5 : 1
        #else
            1
        #endif
    }

    /// Whether the current account's plan is unlimited, read synchronously from the
    /// quota cache (warmed on session load). Only in the single-account view — the
    /// combined view spans accounts that may differ, so it keeps the normal Quota row.
    var quotaIsUnlimited: Bool {
        guard !isMergedView, let id = accountID else { return false }

        return quotaCache.get(id)?.unlimited == true
    }

    /// Whether the Screen section should appear, gating it the way `quotaIsUnlimited`
    /// gates Quota. Single-account: the current account has a Screen key. Combined
    /// view: at least one mergeable account has one, so the row aggregates those
    /// accounts' campaigns (#442); accounts without a key are simply absent from it.
    var screenSectionAvailable: Bool {
        if isMergedView {
            return accounts.mergeableAccounts.contains(where: \.hasScreenAccess)
        }
        return accounts.currentAccount?.hasScreenAccess == true
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
        // No explicit font: inherit the native sidebar row size, matching the section
        // rows above and the favourites below (#572). The "Unlimited" capsule keeps its
        // own smaller caption above.
        .padding(.vertical, 7)
        // The framework dims native list rows when the window isn't the active one;
        // this hand-built row paints its own `.secondary` colors that wouldn't follow,
        // so it would stay fully prominent while every neighbour greyed out (#347).
        // Matching the native inactive treatment keeps the sidebar reading as one piece.
        .opacity(inactiveDimming)
        .help("Your plan has unlimited pads.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota, unlimited plan")
    }

    // MARK: Row chrome

    /// A search-recall row for the Suggested / Favorites groups. Unlike
    /// the top-level section rows (which the `List` selects and styles natively), these
    /// stay custom buttons so they can paint the applied-search highlight, carry context
    /// menus, and be dragged — and they don't feed `SidebarRowWidthKey`, so long names
    /// truncate instead of widening the column. `isSelected` marks the row whose search
    /// is currently applied, so the sidebar shows one honest "you are here" across groups.
    func sidebarSubRow(label: String, icon: String, iconTint: Color = .secondary,
                       isSelected: Bool = false,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // A plain, subtle monochrome glyph — the standard source-list look
                // (Mail/Finder) — rather than a tinted icon tile, which read as too
                // jazzy (#398, reverting #352's tile experiment).
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(isSelected ? Color.accentColor : iconTint)
                    .accessibilityHidden(true)
                    .frame(width: 22)
                Text(label)
                    // No explicit font: inherit the native sidebar row size so the
                    // favourites / suggested searches read as full navigation rows, equal
                    // in weight to the top-level section rows (#572). Hierarchy is
                    // carried by the section headers and selection highlight, not size.
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
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            // The framework desaturates native sidebar rows when the window stops being
            // the active one, but these custom rows paint their own accent/primary
            // colours that don't follow, so they'd stay fully bright while the section
            // rows above them dimmed — the inconsistency #352 flags. Dim in step with the
            // native treatment, matching the unlimited-quota row's fix (#347).
            .opacity(inactiveDimming)
        }
        .buttonStyle(.plain)
        // No explicit hover platter here: this button can be hosted as a List row's
        // root view, and SwiftUI may otherwise try to add `_UIPointerEffectPlatterView`
        // directly to `UIHostingController.view`, logging a hierarchy fault.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// Renders a custom sidebar group (Suggested / Favorites) as a
    /// single, full-width `List` row: clears the framework's row insets, background, and
    /// separator so the group's own padding and highlights show through unchanged, and so
    /// these rows never pick up the native selection chrome reserved for the section rows.
    ///
    /// `.selectionDisabled()` keeps the `List`'s keyboard navigation (and Next/Previous
    /// Section) from landing on these untagged rows: without it, arrow-key nav past the
    /// last real section steps onto the Suggested/Saved/Favorites group rows instead of
    /// cycling among the actual sections (#481). The inner search rows are still
    /// clickable — they're `Button`s, unaffected by row-selection being disabled.
    ///
    /// Only macOS zeroes the row insets: there the `List` (NSTableView) keeps its
    /// standard source-list content margin even with `EdgeInsets()`, so clearing the
    /// insets lets the group span the full row while its sub-rows still line up with
    /// the native section rows. On iOS zeroing the insets drops that leading margin
    /// entirely, pushing the group (the unlimited Quota row, Suggested/Saved/Favorites)
    /// flush to the column's leading edge — left of the native section rows. So there
    /// the default insets are kept and only the background and separator are cleared.
    func sidebarGroupRow() -> some View {
        #if os(macOS)
            listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
        #else
            listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
        #endif
    }
}
