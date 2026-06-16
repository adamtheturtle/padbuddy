//
//  ContentView+SplitColumns.swift
//  coderpad
//

import SwiftUI

// MARK: - The two- and three-column NavigationSplitView layouts

extension MainSplit {
    var threeColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section)
                // Drop the framework's default toggle; `sidebarToggle` below supplies a
                // leading-edge replacement so the content actions don't float past the
                // collapsed-sidebar inset (#337).
                .toolbar(removing: .sidebarToggle)
                // Grow the sidebar's minimum to fit the widest row label. Rounded
                // and only reassigned on a real change, so feeding the measured
                // width back into the same column's min doesn't thrash layout.
                .onPreferenceChange(SidebarRowWidthKey.self) { width in
                    guard width > 0 else { return }
                    let needed = (width + Self.sidebarRowChrome).rounded()
                    if abs(sidebarMinWidth - needed) > 0.5 { sidebarMinWidth = needed }
                }
                .navigationSplitViewColumnWidth(
                    min: sidebarMinWidth,
                    ideal: max(280, sidebarMinWidth),
                    max: max(340, sidebarMinWidth)
                )
                .navigationTitle("")
        } content: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection,
                padSearch: $padSearch,
                questionSearch: $questionSearch
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
            .navigationSplitViewColumnWidth(
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
                questionSelection: $detailQuestion
            )
            .navigationSplitViewColumnWidth(
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
            FindAction(id: section == .questions ? "questions" : "pads") {
                searchFieldFocused = true
            }
        )
        .toolbar { sidebarToggle }
        .navigationTitle(sectionTitle)
        .navigationSubtitle(displaySubtitle)
    }

    var twoColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section)
                // Drop the framework's default toggle; `sidebarToggle` below supplies a
                // leading-edge replacement so the content actions don't float past the
                // collapsed-sidebar inset (#337).
                .toolbar(removing: .sidebarToggle)
                // Grow the sidebar's minimum to fit the widest row label. Rounded
                // and only reassigned on a real change, so feeding the measured
                // width back into the same column's min doesn't thrash layout.
                .onPreferenceChange(SidebarRowWidthKey.self) { width in
                    guard width > 0 else { return }
                    let needed = (width + Self.sidebarRowChrome).rounded()
                    if abs(sidebarMinWidth - needed) > 0.5 { sidebarMinWidth = needed }
                }
                .navigationSplitViewColumnWidth(
                    min: sidebarMinWidth,
                    ideal: max(280, sidebarMinWidth),
                    max: max(340, sidebarMinWidth)
                )
                .navigationTitle("")
        } detail: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection,
                padSearch: $padSearch,
                questionSearch: $questionSearch
            )
            // Organization and Quota publish no count, so this resets the subtitle
            // back to the static section subtitle when switching in from a list.
            .onPreferenceChange(SectionCountKey.self) { sectionCount = $0 }
        }
        .toolbar { sidebarToggle }
        .navigationTitle(sectionTitle)
        .navigationSubtitle(displaySubtitle)
    }
}
