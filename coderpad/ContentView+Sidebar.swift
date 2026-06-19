//
//  ContentView+Sidebar.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {
    @Binding var section: AppSection
    @Environment(\.colorScheme) private var colorScheme
    // Native sidebar rows desaturate when their window stops being the active one;
    // the custom unlimited-quota row has to read this state to dim in step (#347).
    @Environment(\.controlActiveState) private var controlActiveState
    @State var accounts = AccountsStore.shared
    @State var savedSearches = SavedSearchStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var favoritePads = FavoritePadsStore.shared
    @State var questionsCache = QuestionsCacheStore.shared
    @State var padsCache = PadsCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State var nav = AppNavigation.shared
    /// Highlights the Favorite Pads / Favorite Questions section while an item is
    /// dragged over it, the Finder-style cue that dropping there will pin the item.
    @State var droppingFavoritePads = false
    @State var droppingFavoriteQuestions = false
    /// Drives the empty-Favourites drop zone to appear only while a favorite drag is in
    /// flight, so an empty section keeps no resting gap (#444).
    @State var favoriteDragMonitor = FavoriteDragMonitor.shared
    /// The favorite row id a reorder drag is currently hovering, so an insertion line
    /// can be drawn above it (#299). Nil when no reorder drag is in flight.
    @State var reorderTargetID: String?

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
        // If the Screen section becomes unreachable (key removed, or switching to the
        // combined view), step away to Pads so the user isn't left on a gone section.
        .onChange(of: screenSectionAvailable) { _, available in
            if !available, section == .screen { section = .pads }
        }
    }

    var accountID: UUID? {
        accounts.currentAccountID
    }

    /// Whether the current account's plan is unlimited, read synchronously from the
    /// quota cache (warmed on session load). Only in the single-account view — the
    /// combined view spans accounts that may differ, so it keeps the normal Quota row.
    var quotaIsUnlimited: Bool {
        guard !isMergedView, let id = accountID else { return false }

        return quotaCache.get(id)?.unlimited == true
    }

    /// Whether the current account has CoderPad Screen configured, gating the Screen
    /// section the way `quotaIsUnlimited` gates Quota. Single-account only — the
    /// combined view spans accounts and Screen is per-account for now (#432).
    var screenSectionAvailable: Bool {
        guard !isMergedView else { return false }

        return accounts.currentAccount?.makeScreenClient() != nil
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
        // The framework dims native list rows when the window isn't the active one;
        // this hand-built row paints its own `.secondary` colors that wouldn't follow,
        // so it would stay fully prominent while every neighbour greyed out (#347).
        // Matching the native inactive treatment keeps the sidebar reading as one piece.
        .opacity(controlActiveState == .inactive ? 0.5 : 1)
        .help("Your plan has unlimited pads.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota, unlimited plan")
    }

    // MARK: Row chrome

    /// A search-recall row for the Suggested / Saved Searches / Favorites groups. Unlike
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

extension View {
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
