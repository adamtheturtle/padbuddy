//
//  ContentView+SplitColumns.swift
//  coderpad
//

import SwiftUI

// MARK: - The two- and three-column NavigationSplitView layouts

extension MainSplit {
    /// The sidebar column, shared by the two- and three-column layouts. On macOS the
    /// framework's default sidebar toggle is dropped (`sidebarToggle` supplies a
    /// leading-edge replacement so the content actions don't float past the
    /// collapsed-sidebar inset, #337); on iPad we keep the native toggle, which the
    /// system places correctly for touch — the hand-rolled one is buried in the nav-bar
    /// overflow there, hiding navigation behind a tiny "…".
    @ViewBuilder
    var sidebarColumn: some View {
        Sidebar(section: $section)
            #if os(macOS)
            .toolbar(removing: .sidebarToggle)
            #endif
            // Grow the sidebar's minimum to fit the widest row label. Rounded
            // and only reassigned on a real change, so feeding the measured
            // width back into the same column's min doesn't thrash layout.
            .onPreferenceChange(SidebarRowWidthKey.self) { width in
                guard width > 0 else { return }

                let needed = (width + Self.sidebarRowChrome).rounded()
                if abs(sidebarMinWidth - needed) > 0.5 { sidebarMinWidth = needed }
            }
            .macColumnWidth(
                min: sidebarMinWidth,
                ideal: max(280, sidebarMinWidth),
                max: max(340, sidebarMinWidth)
            )
            // Pin the iPad sidebar to one fixed width. `macColumnWidth` is a no-op on
            // iOS (#599), so without this the system re-derives the sidebar width
            // whenever the split swaps between its three-column (Pads/Questions/Screen)
            // and two-column (Organization/Quota) forms — making the leftmost column
            // visibly jump width as the user taps between those sections. The sidebar's
            // content (the section labels) is identical in both, so a fixed width sizes
            // it the same way every time while the content/detail columns stay natively
            // sized, keeping the #599 detail-clipping fix intact.
            #if os(iOS)
            .navigationSplitViewColumnWidth(Self.iPadSidebarWidth)
            #endif
            .navigationTitle("")
    }

    var threeColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection,
                padSearch: $padSearch,
                questionSearch: $questionSearch,
                screenSearch: $screenSearch
            )
            // Round to whole points and only assign on a real change. The measured
            // filter-bar width feeds this column's own min width, so re-writing it
            // with sub-pixel-different (or identical) values would re-invalidate the
            // column mid-layout — which AppKit reports as layout recursion.
            .onPreferenceChange(FilterBarWidthKey.self) { width in
                // Clamp to the ceiling so the column floor never demands more than
                // the window's minimum width can give it. Past this the filter bar
                // scrolls horizontally rather than squeezing and clipping the list.
                // Floor it at a readable baseline so the list can't be dragged to a
                // sliver when a section's filter bar measures narrow.
                let clamped = min(max(width, Self.contentSearchMinWidth),
                                  Self.contentMinWidthCeiling).rounded()
                if contentMinWidth != clamped { contentMinWidth = clamped }
            }
            // Surface the visible list's result count (e.g. "12 pads") as the toolbar
            // subtitle beneath the section title, bubbled up via `SectionCountKey`.
            .onPreferenceChange(SectionCountKey.self) { sectionCount = $0 }
            .macColumnWidth(
                min: effectiveContentMinWidth,
                // `NavigationSplitView` sizes its own minimum off the columns' *ideal*
                // widths, not their `min`s, so below the floor the ideal has to collapse
                // too — otherwise the split stays ~1000pt wide and overflows (clipping)
                // a window the OS has squeezed narrower, no matter how low the `min` is.
                ideal: isBelowWindowFloor ? effectiveContentMinWidth : max(480, contentMinWidth),
                max: max(760, contentMinWidth)
            )
        } detail: {
            // Driven by the debounced detail selection, not the live one, so the
            // detail pane doesn't rebuild on every row of an arrow-key sweep (#326).
            SectionDetail(
                section: section,
                padSelection: $detailPad,
                questionSelection: $detailQuestion,
                screenSearch: $screenSearch
            )
            .macColumnWidth(
                min: effectiveDetailMinWidth,
                ideal: isBelowWindowFloor ? effectiveDetailMinWidth : 520
            )
        }
        // Attach search to the whole split rather than a single column. The system
        // then hosts it as one search item pinned at the window's top-right (the
        // Passwords/Finder position), so it can't stretch across and overlap the
        // middle list pane the way a column-scoped field did. The text is routed to
        // the visible section by `activeSearch`; ⌘F focuses it via the FindAction.
        .searchable(text: activeSearch, placement: .toolbar, prompt: searchPrompt)
        .searchFocused($searchFieldFocused)
        .focusedSceneValue(
            \.findAction,
            FindAction(id: section == .questions ? "questions" : "pads", hasSystemFindShortcut: true) {
                searchFieldFocused = true
            }
        )
        #if os(macOS)
        .toolbar { sidebarToggle }
        #endif
        .navigationTitle(sectionTitle)
        // `navigationSubtitle` is macOS (and iOS 26+) only; on iPad 18 the section
        // subtitle is simply omitted from the navigation bar.
        #if os(macOS)
        .navigationSubtitle(displaySubtitle)
        #endif
    }

    var twoColumnSplit: some View {
        listSearchable(
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } detail: {
                SectionContent(
                    section: section,
                    padSelection: $padSelection,
                    questionSelection: $questionSelection,
                    padSearch: $padSearch,
                    questionSearch: $questionSearch,
                    screenSearch: $screenSearch
                )
                // Organization and Quota publish no count, so this resets the subtitle
                // back to the static section subtitle when switching in from a list.
                .onPreferenceChange(SectionCountKey.self) { sectionCount = $0 }
            }
        )
        #if os(macOS)
        .toolbar { sidebarToggle }
        #endif
        .navigationTitle(sectionTitle)
        // `navigationSubtitle` is macOS (and iOS 26+) only; on iPad 18 the section
        // subtitle is simply omitted from the navigation bar.
        #if os(macOS)
        .navigationSubtitle(displaySubtitle)
        #endif
    }

    /// Attaches the same window-toolbar search field `threeColumnSplit` carries, but
    /// only for the list-backed sections — so a Pads/Questions window with its detail
    /// pane hidden (#394) keeps search, while Organization/Quota (which have nothing to
    /// search) don't gain a useless field. Mirrors the wiring in `threeColumnSplit`.
    @ViewBuilder
    func listSearchable(_ content: some View) -> some View {
        if sectionHasDetail {
            content
                .searchable(text: activeSearch, placement: .toolbar, prompt: searchPrompt)
                .searchFocused($searchFieldFocused)
                .focusedSceneValue(
                    \.findAction,
                    FindAction(id: section == .questions ? "questions" : "pads") {
                        searchFieldFocused = true
                    }
                )
        } else {
            content
        }
    }
}

extension View {
    /// Applies a fixed `navigationSplitViewColumnWidth` on macOS only, passing the view
    /// through untouched on iOS. The column widths here are hand-tuned for an AppKit
    /// window the user can drag to any size; on iPad they backfire. `NavigationSplitView`
    /// sizes its columns off these ideals/maxes, and the macOS-sized detail ideal (520)
    /// plus its open-ended `max` inflate the split wider than a portrait iPad mini (744pt) —
    /// the detail pane then slides under the opaque list column on the leading edge and off
    /// the screen on the trailing edge (#599). iPad has no draggable window floor to relax
    /// these (``isBelowWindowFloor`` is permanently false there), so the fix is to let the
    /// system size the columns natively, which fits them to the device by design.
    @ViewBuilder
    func macColumnWidth(min: CGFloat, ideal: CGFloat, max: CGFloat? = nil) -> some View {
        #if os(macOS)
            if let max {
                navigationSplitViewColumnWidth(min: min, ideal: ideal, max: max)
            } else {
                navigationSplitViewColumnWidth(min: min, ideal: ideal)
            }
        #else
            self
        #endif
    }
}
