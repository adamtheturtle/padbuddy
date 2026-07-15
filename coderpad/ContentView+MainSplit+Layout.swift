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
            navigationStatusBanner(store: store, network: network, monitor: monitor)
            Group {
                if showsDetailColumn {
                    threeColumnSplit
                } else {
                    twoColumnSplit
                }
            }
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
            // iPad gets no floor: there's no `NSWindow.contentMinSize` to honor, and the
            // `WindowMinWidth` width reporter is a no-op on iOS, so `containerWidth` stays
            // 0 and `isBelowWindowFloor` never trips. A forced `minWidth` there would stay
            // pinned even when the window is narrower (portrait on a small iPad, Split View,
            // Stage Manager, Slide Over) — making the split wider than the window, which
            // SwiftUI centers, clipping the leading column's first characters off the edge.
            // Letting the iPad split take the window's true width keeps it inside the bounds.
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
            // Enable View ▸ Customize Toolbar… — SwiftUI leaves the merged window
            // toolbar's `allowsUserCustomization` off for this split + search setup,
            // disabling the menu item even though every toolbar is customizable (#408).
            .background(ToolbarCustomizationEnabler())
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

                section = NavigationSessionLoader.persistedSection(for: store)
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
                let key = store.isMergedView
                    ? "section.merged"
                    : store.currentAccount.map { "section.\($0.id.uuidString)" }
                if let key { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
            }
            .onChange(of: store.currentAccountID) { _, _ in
                padSelection = nil
                questionSelection = nil
                restoredSections.removeAll()
            }
            // Switching into or out of the combined view changes what the panes show, so
            // drop any stale selection from the previous mode.
            .onChange(of: store.isMergedView) { _, _ in
                padSelection = nil
                questionSelection = nil
                restoredSections.removeAll()
            }
    }

    /// Selection observers: restore-on-launch, per-pane persistence, the debounced
    /// detail-pane settle, and the sidebar-toggle scene value.
    var decoratedSelection: some View {
        decoratedObservers
            // Resume the row the user left selected last session, once its list has loaded
            // (#273). Re-runs when the section is restored at launch and when rows arrive.
            .onChange(of: restoreProbe, initial: true) { _, _ in scheduleRestoreSelectionIfNeeded() }
            .onChange(of: padSelection) { _, sel in
                if sel != nil { requestPreferredCompactColumn(.detail) }
                persistSelection(padID: sel?.id, questionID: nil)
            }
            .onChange(of: questionSelection) { _, sel in
                if sel != nil { requestPreferredCompactColumn(.detail) }
                persistSelection(padID: nil, questionID: sel?.id)
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
                SidebarToggleAction(collapsed: columnVisibility != .all, perform: toggleSidebar)
            )
    }
}
