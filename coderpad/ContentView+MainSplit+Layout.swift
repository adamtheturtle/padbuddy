//
//  ContentView+MainSplit+Layout.swift
//  coderpad
//
//  Split out of ContentView+MainSplit.swift to keep each file under the length limit.
//  These compose `MainSplit.body` from the split layout plus the layout/session and
//  selection observer groups; they stay internal (not private) so `body`, which lives
//  in the main file, can reach them across the extension boundary.
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

extension MainSplit {
    /// The split layout: the offline/unauthorized banner, the two- or three-column
    /// split, and the window-floor / separator-hider / toolbar-customization backgrounds.
    var splitLayout: some View {
        VStack(spacing: 0) {
            spatialSplit
                // Floor the layout at the active section's needs so a free drag can't
                // crush the columns — but only while the window is at or above that floor.
                // The moment the *OS* forces the window below it (Split View, tiling, Stage
                // Manager, a small/scaled display — none of which honor `contentMinSize`),
                // drop the floor (`minWidth: nil`) so the content takes the window's true
                // width instead of staying oversized and *centering*, which bled the list
                // and filter bar off the leading edge and the detail off the trailing. The
                // relaxed column minimums (`effective*MinWidth`) then let the split compress
                // toward the window. `NavigationSplitView` still keeps a sizable intrinsic
                // minimum it won't shrink past, so when the OS tile is narrower than even that,
                // `maxWidth: .infinity` + `.leading` pins the split's leading edge to the
                // window so the residual overflow falls off the *trailing* (detail) edge —
                // keeping the list and filter bar readable instead of bleeding off the left.
                // iPad gets no floor: there's no `NSWindow.contentMinSize` to honor, and a
                // forced `minWidth` would stay pinned even when the window is narrower
                // (portrait on a small iPad, Split View, Stage Manager, Slide Over) — making
                // the split wider than the window, which SwiftUI centers, clipping the leading
                // column's first characters off the edge. Letting the iPad split take the
                // window's true width keeps it inside the bounds. visionOS also avoids a
                // hard floor, but `WindowMinWidth` reports the live spatial-window width so the
                // adaptive column collapse can still respond to resizing (#3319).
                .frame(minWidth: windowFloorMinWidth, maxWidth: .infinity, alignment: .leading)
                // Pin the drag floor on the host window itself, since `.frame(minWidth:)`
                // alone doesn't reliably reach the window's `contentMinSize` from inside a
                // NavigationSplitView. This view also reports the window's *true* content
                // width back into `containerWidth` (driving the sidebar auto-collapse and the
                // below-floor detection): a SwiftUI reader here would only ever see the
                // floored frame width and never notice the OS squeezing the window narrower.
                .background(WindowMinWidth(width: windowMinWidth, onContentWidth: updateContainerWidth))
                // Suppress AppKit's sidebar/content tracking-separator line while the
                // sidebar is collapsed — with no sidebar divider to track it draws a stray
                // vertical line right after the leading actions (#337).
                .background(SidebarSeparatorHider(collapsed: columnVisibility != .all))
                // Remap a collapsed sidebar across the 2-/3-column switch: a collapse
                // stored as .detailOnly by a two-column section hides BOTH the sidebar
                // and the list once a three-column section mounts, and a three-column
                // collapse (.doubleColumn) reads as sidebar-visible in a two-column
                // one, revealing a sidebar the user had collapsed (#1663).
                .onChange(of: showsDetailColumn) { hadThreeColumns, hasThreeColumns in
                    guard columnVisibility != .all else { return }

                    if hasThreeColumns, !hadThreeColumns, columnVisibility == .detailOnly {
                        columnVisibility = .doubleColumn
                    } else if hadThreeColumns, !hasThreeColumns, columnVisibility == .doubleColumn {
                        columnVisibility = .detailOnly
                    }
                }
                // Enable View ▸ Customize Toolbar… — SwiftUI leaves the merged window
                // toolbar's `allowsUserCustomization` off for this split + search setup,
                // disabling the menu item even though every toolbar is customizable (#408).
                .background(ToolbarCustomizationEnabler())
        }
    }

    @ViewBuilder
    private var spatialSplit: some View {
        #if os(visionOS)
            HStack(alignment: .top, spacing: 18) {
                Sidebar(section: $section)
                    .frame(width: Self.visionNavigationRailWidth)

                VStack(spacing: 0) {
                    navigationStatusBanner(store: store, network: network, monitor: monitor, section: section)
                    visionSpatialColumns
                }
                .visionSpatialPanel()
            }
        #else
            navigationStatusBanner(store: store, network: network, monitor: monitor, section: section)
            splitColumns
                .visionSpatialPanel()
        #endif
    }

    private var visionSpatialColumns: some View {
        visionSpatialSearchable(
            Group {
                if showsDetailColumn {
                    HStack(spacing: 0) {
                        SectionContent(
                            section: section,
                            padSelection: $padSelection,
                            questionSelection: $questionSelection,
                            padSearch: $padSearch,
                            questionSearch: $questionSearch,
                            screenSearch: $screenSearch
                        )
                        .frame(minWidth: effectiveContentMinWidth,
                               idealWidth: 380,
                               maxWidth: 440,
                               maxHeight: .infinity)

                        Divider()

                        SectionDetail(
                            section: section,
                            padSelection: $detailPad,
                            questionSelection: $detailQuestion,
                            screenSearch: $screenSearch
                        )
                        .frame(minWidth: effectiveDetailMinWidth,
                               idealWidth: 520,
                               maxWidth: .infinity,
                               maxHeight: .infinity)
                    }
                } else {
                    SectionContent(
                        section: section,
                        padSelection: $padSelection,
                        questionSelection: $questionSelection,
                        padSearch: $padSearch,
                        questionSearch: $questionSearch,
                        screenSearch: $screenSearch
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
    }

    @ViewBuilder
    private func visionSpatialSearchable(_ content: some View) -> some View {
        if sectionHasDetail {
            content
                .searchable(text: activeSearch, placement: .toolbar, prompt: searchPrompt)
                .searchFocused($searchFieldFocused)
                .focusedSceneValue(
                    \.findAction,
                    FindAction(id: section == .questions ? "questions" : "pads",
                               publisherID: findActionPublisherID,
                               hasSystemFindShortcut: true) {
                        searchFieldFocused = true
                    }
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private var splitColumns: some View {
        if showsDetailColumn {
            threeColumnSplit
        } else {
            twoColumnSplit
        }
    }

    /// Layout/session observers: width-driven sidebar collapse, visibility persistence,
    /// the per-session load task, and section/account/mode changes.
    var decoratedObservers: some View {
        splitLayout
            .onChange(of: containerWidth) { _, width in updateSidebarCollapse(for: width) }
            // Honor a deliberate reopen in a too-narrow window so the auto-collapse doesn't
            // fight the toggle (#307), and remember a deliberate collapse for next launch (#273).
            .onChange(of: columnVisibility) { _, visibility in
                handleVisibilityChange(to: visibility)
                persistSidebarCollapsed(visibility)
            }
            // A section change moves the threshold (three columns vs. two), so
            // re-evaluate against the width we already know.
            .onChange(of: section) { _, newValue in
                let available = NavigationSessionLoader.availableSection(from: newValue)
                guard available == newValue else {
                    section = available
                    return
                }

                requestPreferredCompactColumn(preferredCompactColumnForCurrentSection)
                updateSidebarCollapse(for: containerWidth)
                Task {
                    await NavigationSessionLoader.warmInactiveSections(store: store, active: newValue)
                }
                // The toolbar count subtitle no longer needs clearing here: it's tagged
                // with the section it was published for (`AppNavigation.sectionCountSection`),
                // so `displaySubtitle` ignores a count left over from the section we left
                // until the new pane republishes. Clearing synchronously here (while the new
                // count's publish lands a frame later) is what left the subtitle blank for a
                // frame — the flash we're avoiding.
            }
            .task(id: NavigationSessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
                await Task.yield()

                // This window's own choice first, then the shared last-used one. The
                // shared key alone meant two windows under the same account overwrote
                // each other's section, so neither reopened where it was left (#2657).
                section = NavigationSessionLoader.section(fromSceneValue: persistedWindowSection)
                    ?? NavigationSessionLoader.persistedSection(for: store)
                    ?? NavigationSessionLoader.availableSection(from: section)
                // Section is settled, so the collapse can map to the right column count.
                restoreSidebarCollapsedIfNeeded()
                await NavigationSessionLoader.load(
                    store: store,
                    directory: directory,
                    monitor: monitor,
                    active: section
                )
            }
            .onChange(of: section) { _, newValue in
                // This window's own copy, and the shared seed a brand-new window
                // starts from (#2657).
                persistedWindowSection = newValue.rawValue
                let key = store.isMergedView
                    ? "section.merged"
                    : store.currentAccount.map { "section.\($0.id.uuidString)" }
                if let key {
                    UserDefaults.standard.set(newValue.rawValue, forKey: key)
                }
            }
            .onChange(of: store.currentAccountID) { _, _ in
                padSelection = nil
                questionSelection = nil
                clearScreenSelection()
                restoredSections.removeAll()
            }
            // Switching into or out of the combined view changes what the panes show, so
            // drop any stale selection from the previous mode.
            .onChange(of: store.isMergedView) { _, _ in
                padSelection = nil
                questionSelection = nil
                clearScreenSelection()
                restoredSections.removeAll()
            }
    }

    /// Drops the Screen drill-down state alongside the pad/question selections when
    /// the account or view mode changes: the selected campaign (and its account
    /// routing and subtitle) belongs to the previous account's Screen client, so
    /// leaving it active shows another org's candidates in the detail column (#711).
    private func clearScreenSelection() {
        windowNav.publishScreenCampaign(nil, accountID: nil)
        windowNav.screenTestsSubtitle = ""
        windowNav.screenTestsSubtitleOwner = nil
        mergedRouting.selectedScreenAccountID = nil
    }

    /// Selection observers: restore-on-launch, per-pane persistence, the debounced
    /// detail-pane settle, and the sidebar-toggle scene value.
    var decoratedSelection: some View {
        decoratedObservers
            // Resume the row the user left selected last session, once its list has loaded
            // (#273). Re-runs when the section is restored at launch and when rows arrive.
            .onChange(of: restoreProbe, initial: true) { _, _ in scheduleRestoreSelectionIfNeeded() }
            .onChange(of: padSelection) { _, sel in
                if sel != nil {
                    requestPreferredCompactColumn(.detail)
                }
                persistSelection(padID: sel?.id, questionID: nil)
            }
            .onChange(of: questionSelection) { _, sel in
                if sel != nil {
                    requestPreferredCompactColumn(.detail)
                }
                persistSelection(padID: nil, questionID: sel?.id)
            }
            .onChange(of: preferredCompactColumn) { _, column in
                releaseCompactPadDetailIfNeeded(for: column)
            }
            // Settle the live selection into the detail pane, debouncing arrow-key
            // sweeps so the heavy detail view is rebuilt only on the row the user lands
            // on, not every row passed through (#326). The task restarts on each change,
            // cancelling any pending settle.
            .task(id: padSelection) { await settleDetailPad() }
            .task(id: questionSelection) { await settleDetailQuestion() }
            // Publish the sidebar toggle so View ▸ Show/Hide Sidebar (⌃⌘S) flips the same
            // `columnVisibility` state as the toolbar button (#396). Scene-scoped, so the
            // command is enabled only while the main window is frontmost.
            .focusedSceneValue(
                \.sidebarToggleAction,
                SidebarToggleAction(collapsed: columnVisibility != .all,
                                    instanceToken: sidebarToggleToken,
                                    perform: toggleSidebar)
            )
    }
}
