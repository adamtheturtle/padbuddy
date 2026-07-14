//
//  ContentView+SplitSidebar.swift
//  coderpad
//

import SwiftUI

// MARK: - Sidebar collapse/restore (#273, #307) and column-width math

extension MainSplit {
    /// Smallest container width at which every visible column fits at its measured
    /// minimum and the sidebar can stay open. Derived from the live measurements
    /// (`sidebarMinWidth`, `contentMinWidth`) rather than a hardcoded constant, so
    /// it tracks label, font, and filter changes automatically.
    var sidebarVisibleFloor: CGFloat {
        sectionHasDetail
            ? sidebarMinWidth + contentMinWidth + Self.detailMinWidth
            : sidebarMinWidth + Self.detailMinWidth
    }

    /// Window floor once the sidebar is collapsed: the remaining columns at their
    /// minimums. Lets the window shrink below ``sidebarVisibleFloor`` gracefully —
    /// the sidebar hides — instead of crushing the sidebar against the edge. Kept
    /// section-independent so the window minimum doesn't jump when switching tabs.
    var collapsedFloor: CGFloat {
        contentMinWidth + Self.detailMinWidth
    }

    /// The host window's hard minimum content width — a single honest floor pinned on
    /// the `NSWindow` (see ``WindowMinWidth``), because `.frame(minWidth:)` inside a
    /// `NavigationSplitView` doesn't reliably reach the window's `contentMinSize`, so
    /// without it the window can be dragged narrow enough to crush/overlap the panes.
    /// Pads/Questions floor at list + detail; single-pane sections (Organization,
    /// Quota) floor at their lone content pane. Keyed off the section, not the live
    /// column visibility, so it stays constant while the user drags — the width-driven
    /// sidebar collapse handles narrowing, and the window never collapses to a
    /// width-forced single column (see #293).
    var windowMinWidth: CGFloat {
        sectionHasDetail ? collapsedFloor : Self.detailMinWidth
    }

    /// The minimum width pinned on the split's frame. On macOS it's the honest drag
    /// floor (``windowMinWidth``), dropped to `nil` once the OS squeezes the window below
    /// it (``isBelowWindowFloor``) so the split compresses instead of overflowing. On iPad
    /// it's always `nil`: there's no `NSWindow.contentMinSize` to back up a floor and the
    /// ``WindowMinWidth`` width reporter is a no-op there, so `isBelowWindowFloor` can never
    /// trip to release a pinned floor — leaving a forced `minWidth` to overflow (and clip
    /// the leading column of) any window narrower than it.
    var windowFloorMinWidth: CGFloat? {
        #if os(macOS)
            isBelowWindowFloor ? nil : windowMinWidth
        #else
            nil
        #endif
    }

    /// The column to show after choosing a sidebar section in compact width. Sections
    /// with a list/detail pair should advance to the list; single-pane sections are
    /// hosted in the split's detail closure and should appear directly.
    var preferredCompactColumnForCurrentSection: NavigationSplitViewColumn {
        sectionHasDetail ? .content : .detail
    }

    /// Queues a compact-column change for the next main-actor turn, replacing any
    /// earlier request made during the same update pass. Section changes can also
    /// adjust column visibility, and row restoration can immediately request detail;
    /// coalescing keeps those from tripping SwiftUI's navigation update guard.
    func requestPreferredCompactColumn(_ column: NavigationSplitViewColumn) {
        pendingPreferredCompactColumn = column
        guard !preferredCompactColumnUpdateScheduled else { return }

        preferredCompactColumnUpdateScheduled = true
        DispatchQueue.main.async {
            preferredCompactColumnUpdateScheduled = false
            guard let column = pendingPreferredCompactColumn else { return }

            pendingPreferredCompactColumn = nil
            if preferredCompactColumn != column {
                preferredCompactColumn = column
            }
        }
    }

    /// True when the OS has forced the window narrower than its honest drag floor
    /// (``windowMinWidth``) — only reachable via Split View, tiling, Stage Manager, or a
    /// small/scaled display, since the `NSWindow`'s `contentMinSize` stops a free drag at
    /// the floor. When it is, the column minimums relax (below) so the split compresses to
    /// the available width instead of overflowing and clipping its leading edge — the list
    /// and filter bar that otherwise vanish past the window's left edge.
    var isBelowWindowFloor: Bool {
        containerWidth > 0 && containerWidth < windowMinWidth
    }

    /// The content column's effective minimum width. Relaxes to
    /// ``narrowOverrideColumnMin`` while the user is keeping the sidebar open in a
    /// too-narrow window (#307), or whenever the OS has squeezed the window below the
    /// drag floor (``isBelowWindowFloor``), so the columns shrink to fit rather than
    /// clip — in the first case to free room for the sidebar, in the second to fit the
    /// whole split into a width smaller than the columns' normal minimums would allow.
    var effectiveContentMinWidth: CGFloat {
        (keepSidebarWhileNarrow || isBelowWindowFloor)
            ? min(Self.narrowOverrideColumnMin, contentMinWidth)
            : contentMinWidth
    }

    /// The detail column's effective minimum width. Relaxes alongside the content
    /// column while the sidebar is kept open in a too-narrow window (#307) or the OS has
    /// squeezed the window below the drag floor (``isBelowWindowFloor``).
    var effectiveDetailMinWidth: CGFloat {
        (keepSidebarWhileNarrow || isBelowWindowFloor)
            ? min(Self.narrowOverrideColumnMin, Self.detailMinWidth)
            : Self.detailMinWidth
    }

    func updateContainerWidth(_ width: CGFloat) {
        guard containerWidth != width else { return }

        DispatchQueue.main.async {
            if containerWidth != width { containerWidth = width }
        }
    }

    /// Collapses the sidebar when the container is too narrow to hold every column
    /// at its minimum, and restores it once there's room again — but only when the
    /// collapse was ours to begin with, never a manual one.
    func updateSidebarCollapse(for width: CGFloat) {
        guard width > 0 else { return }

        if width < sidebarVisibleFloor {
            // Stand down while the user has chosen to keep the sidebar open in a
            // too-narrow window, so we don't yank it shut mid-expand (#307).
            guard !keepSidebarWhileNarrow else { return }

            if columnVisibility == .all {
                withAnimation(reduceMotion ? nil : .smooth) {
                    columnVisibility = sectionHasDetail ? .doubleColumn : .detailOnly
                }
                autoCollapsed = true
            }
        } else {
            // Wide enough for every column again: the narrow-window override no longer
            // applies, and we restore anything we auto-collapsed.
            keepSidebarWhileNarrow = false
            if autoCollapsed {
                withAnimation(reduceMotion ? nil : .smooth) { columnVisibility = .all }
                autoCollapsed = false
            }
        }
    }

    /// Reacts to the sidebar being toggled while the window is too narrow to hold every
    /// column. A manual reopen there is a deliberate choice — the user wants the sidebar
    /// even though it overlaps — so we honor it and suppress the width-driven
    /// auto-collapse until the window grows wide again or the sidebar is closed (#307).
    /// Above the floor the normal regime governs, so this is a no-op.
    func handleVisibilityChange(to visibility: NavigationSplitViewVisibility) {
        guard containerWidth > 0, containerWidth < sidebarVisibleFloor else { return }

        if visibility == .all {
            keepSidebarWhileNarrow = true
            autoCollapsed = false
        } else {
            keepSidebarWhileNarrow = false
        }
    }

    /// Remembers whether the user left the sidebar collapsed, so the next launch
    /// resumes that choice (#273). Skips width-driven auto-collapses (`autoCollapsed`)
    /// — those reflect a too-narrow window, not a deliberate decision — so only a real
    /// toggle is persisted.
    func persistSidebarCollapsed(_ visibility: NavigationSplitViewVisibility) {
        guard !autoCollapsed else { return }

        UserDefaults.standard.set(visibility != .all, forKey: Self.sidebarCollapsedKey)
    }

    /// Restores the saved sidebar collapse state once per launch (#273). Maps the
    /// stored Bool back to the hidden state that matches the current column count
    /// (`.doubleColumn` keeps the content list beside the detail in three-column
    /// sections; `.detailOnly` is the lone hide for two-column ones). The width-driven
    /// auto-collapse still corrects this afterward if the window is too narrow to hold
    /// an expanded sidebar, so a restored "expanded" never overflows a small window.
    func restoreSidebarCollapsedIfNeeded() {
        guard !didRestoreSidebar else { return }

        didRestoreSidebar = true
        guard UserDefaults.standard.object(forKey: Self.sidebarCollapsedKey) != nil else { return }

        let collapsed = UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey)
        let target: NavigationSplitViewVisibility = collapsed
            ? (sectionHasDetail ? .doubleColumn : .detailOnly)
            : .all
        if columnVisibility != target { columnVisibility = target }
    }

    /// Flips the sidebar between fully open and collapsed, mapping to the hidden state
    /// that matches the current column count (`.doubleColumn` keeps the list beside the
    /// detail in three-column sections; `.detailOnly` is the lone hide for two-column
    /// ones). The existing `onChange(of: columnVisibility)` handlers pick this up, so a
    /// toggle here persists (#273) and stands down the width auto-collapse (#307) just
    /// like the system toggle did.
    func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .smooth) {
            if columnVisibility == .all {
                columnVisibility = sectionHasDetail ? .doubleColumn : .detailOnly
            } else {
                columnVisibility = .all
            }
        }
    }

    // A hand-rolled replacement for the `NavigationSplitView` default sidebar toggle,
    // which we remove via `.toolbar(removing: .sidebarToggle)`. Mail does the same: a
    // `.navigation`-placement toggle pinned to the toolbar's leading edge, so the
    // content column's action cluster (Reload/New) packs right up against it instead
    // of floating past AppKit's phantom collapsed-sidebar inset (#337). Driven by our
    // own `columnVisibility` rather than the AppKit `toggleSidebar` selector, since we
    // already own that state. The ⌃⌘S shortcut lives on the View ▸ Show/Hide Sidebar
    // menu item (#396) — its conventional home — so it isn't duplicated here.
    //
    // macOS only: on iPad we keep `NavigationSplitView`'s native sidebar/column toggle
    // (we don't `.toolbar(removing: .sidebarToggle)` there), which the system places and
    // sizes correctly for touch. The hand-rolled `.navigation` button gets shoved into
    // the iPad nav-bar overflow, hiding all navigation behind a tiny "…" — so this
    // item exists only on macOS and the framework's toggle stands in on iOS.
    #if os(macOS)
        @ToolbarContentBuilder
        var sidebarToggle: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .help("Show or hide the sidebar")
            }
        }
    #endif
}
