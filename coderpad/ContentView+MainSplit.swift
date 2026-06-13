//
//  ContentView+MainSplit.swift
//  coderpad
//

import AppKit
import SwiftUI

// MARK: - Split into small structs to reduce body type complexity

struct MainSplit: View {
    @State private var store = AccountsStore.shared
    @Binding var section: AppSection
    let directory: OrgDirectory
    let monitor: AccountHealthMonitor

    @State private var padSelection: Pad?
    @State private var questionSelection: Question?

    /// The list search text, lifted out of `PadsView`/`QuestionsView` so the
    /// `.searchable` field can attach to the `NavigationSplitView` itself. That
    /// places it at the trailing edge of the *window* toolbar (over the detail
    /// pane, Finder-style) instead of the content column — where the content/detail
    /// divider used to slide the list under it. Each section keeps its own text; the
    /// active one is routed to the single searchable field via ``activeSearch``.
    @State private var padSearch = ""
    @State private var questionSearch = ""

    /// Drives the lifted searchable field's focus so ⌘F (via ``FindAction``) can
    /// still jump straight into it from anywhere in the window.
    @FocusState private var searchFieldFocused: Bool

    /// Routes the single window-toolbar search field to the visible section's text.
    /// Only `threeColumnSplit` (Pads/Questions) carries the field, so the default
    /// arm simply covers Pads.
    private var activeSearch: Binding<String> {
        section == .questions ? $questionSearch : $padSearch
    }

    private var searchPrompt: Text {
        Text(section == .questions ? "Search questions" : "Search pads")
    }

    /// Drives the sidebar collapse/expand. With the title bar hidden there's no
    /// system toolbar to host the automatic sidebar toggle, so we own this state
    /// and surface our own toggle in the titlebar instead.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Whether the sidebar's current collapse was driven by the window becoming too
    /// narrow rather than a manual toggle. We only auto-expand what we auto-collapsed,
    /// so a deliberate choice is never overridden by a resize.
    @State private var autoCollapsed = false

    /// Latest observed width of the split-view container, kept so a section change
    /// (which moves the collapse threshold) can be re-evaluated without waiting for
    /// the next resize.
    @State private var containerWidth: CGFloat = 0

    /// Floor for the content column: the natural width of the active section's
    /// filter bar, so it can never be dragged too thin to hold all filters.
    @State private var contentMinWidth: CGFloat = 380

    /// Floor for the sidebar column, derived at runtime from the widest row label
    /// (see ``SidebarRowWidthKey``) plus the row's fixed chrome, so the longest
    /// label never wraps or truncates regardless of font or label changes.
    @State private var sidebarMinWidth: CGFloat = 220

    /// Non-text width of a sidebar row: the VStack + row horizontal insets, the
    /// icon column and its spacing, and trailing breathing room before the
    /// selection pill's edge. Added to the measured label width.
    private static let sidebarRowChrome: CGFloat = 110

    /// Minimum width of the detail column. A single source shared by the column
    /// definition and the auto-collapse/window-floor math, so they can't drift.
    private static let detailMinWidth: CGFloat = 360

    /// Ceiling for ``contentMinWidth``. The filter bar reports its full natural
    /// width, which can exceed the budget the window's own minimum width leaves
    /// for this column once the sidebar and detail minimums are subtracted. Left
    /// uncapped, shrinking the window inflates this floor past that budget and the
    /// list pane gets clipped instead of the filter bar simply scrolling. Holding
    /// the floor here keeps sidebar + content + detail within the window minimum.
    private static let contentMinWidthCeiling: CGFloat = 380

    /// Hard floor for ``contentMinWidth``. The search field itself now lives on the
    /// split view (trailing window toolbar, over the detail pane) rather than this
    /// column, but a baseline keeps the list readable: a section whose filter bar
    /// measures narrower than this shouldn't collapse to a sliver. Kept below the
    /// ceiling so the adaptive filter-bar narrowing still applies in the band above.
    private static let contentSearchMinWidth: CGFloat = 340

    /// Smallest container width at which every visible column fits at its measured
    /// minimum and the sidebar can stay open. Derived from the live measurements
    /// (`sidebarMinWidth`, `contentMinWidth`) rather than a hardcoded constant, so
    /// it tracks label, font, and filter changes automatically.
    private var sidebarVisibleFloor: CGFloat {
        sectionHasDetail
            ? sidebarMinWidth + contentMinWidth + Self.detailMinWidth
            : sidebarMinWidth + Self.detailMinWidth
    }

    /// Window floor once the sidebar is collapsed: the remaining columns at their
    /// minimums. Lets the window shrink below ``sidebarVisibleFloor`` gracefully —
    /// the sidebar hides — instead of crushing the sidebar against the edge. Kept
    /// section-independent so the window minimum doesn't jump when switching tabs.
    private var collapsedFloor: CGFloat {
        contentMinWidth + Self.detailMinWidth
    }

    private var isSidebarCollapsed: Bool {
        columnVisibility != .all
    }

    private func toggleSidebar() {
        let willOpen = isSidebarCollapsed
        withAnimation(.smooth) {
            if isSidebarCollapsed {
                columnVisibility = .all
            } else {
                columnVisibility = sectionHasDetail ? .doubleColumn : .detailOnly
            }
        }
        // A manual toggle takes ownership: stop tracking this as a width-driven
        // collapse so a later resize doesn't undo the user's choice.
        autoCollapsed = false
        // Opening the sidebar while the window is narrower than every column's
        // combined minimum would squeeze the columns and clip the sidebar — the
        // auto-collapse only reacts to resizes, not to this manual open. Grow the
        // window to fit, the way Mail does, so the sidebar always shows in full.
        if willOpen, containerWidth > 0, containerWidth < sidebarVisibleFloor {
            growWindowToFitSidebar()
        }
    }

    /// Widens the key window enough that every column fits at its minimum, so a
    /// manual sidebar open at a narrow width never clips the sidebar. Clamps to the
    /// visible screen and slides the window left if its right edge would spill over.
    /// A few points of slack keep the resulting width just above
    /// ``sidebarVisibleFloor`` so the auto-collapse doesn't immediately re-hide it.
    private func growWindowToFitSidebar() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let delta = sidebarVisibleFloor - containerWidth + 4
        guard delta > 0 else { return }
        var frame = window.frame
        frame.size.width += delta
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.size.width, visible.width)
            if frame.maxX > visible.maxX {
                frame.origin.x = max(visible.minX, visible.maxX - frame.size.width)
            }
        }
        window.setFrame(frame, display: true, animate: true)
    }

    /// Collapses the sidebar when the container is too narrow to hold every column
    /// at its minimum, and restores it once there's room again — but only when the
    /// collapse was ours to begin with, never a manual one.
    private func updateSidebarCollapse(for width: CGFloat) {
        guard width > 0 else { return }
        if width < sidebarVisibleFloor {
            if columnVisibility == .all {
                withAnimation(.smooth) {
                    columnVisibility = sectionHasDetail ? .doubleColumn : .detailOnly
                }
                autoCollapsed = true
            }
        } else if autoCollapsed {
            withAnimation(.smooth) { columnVisibility = .all }
            autoCollapsed = false
        }
    }

    /// Pads and Questions drive a detail pane; Organization and Quota are
    /// single-pane sections, so they drop the third column entirely.
    private var sectionHasDetail: Bool {
        switch section {
        case .pads, .questions: true
        case .organization, .quota: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // In the combined view, per-account fetch failures surface inline in the
            // merged list, so the single-account unauthorized banner is suppressed.
            if !store.isMergedView, let id = store.currentAccountID, monitor.isUnauthorized(id) {
                UnauthorizedBanner(monitor: monitor)
            }
            Group {
                if sectionHasDetail {
                    threeColumnSplit
                } else {
                    twoColumnSplit
                }
            }
            // Floor the window at the collapsed layout's needs; auto-collapse keeps
            // it usable between here and `sidebarVisibleFloor`.
            .frame(minWidth: collapsedFloor)
            // Observe the container width without disturbing layout (a background
            // reader, not a wrapping GeometryReader, so the frame min still
            // propagates to the window). Drives the sidebar's auto-collapse.
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size.width, initial: true) { _, width in
                            containerWidth = width
                        }
                }
            )
        }
        .onChange(of: containerWidth) { _, width in updateSidebarCollapse(for: width) }
        // A section change moves the threshold (three columns vs. two), so
        // re-evaluate against the width we already know.
        .onChange(of: section) { _, _ in updateSidebarCollapse(for: containerWidth) }
        // Pin the sidebar toggle in the titlebar (right of the traffic lights),
        // which the hidden title bar leaves transparent over the sidebar.
        .background(
            TitlebarLeadingAccessory {
                SidebarToggleButton(isCollapsed: isSidebarCollapsed, action: toggleSidebar)
            }
        )
        // Lets the View menu's "Customize Toolbar…" command enable itself only
        // while a main window (with its customizable section toolbar) is frontmost.
        .focusedSceneValue(\.canCustomizeToolbar, true)
        .task(id: SessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
            if store.isMergedView {
                if let raw = UserDefaults.standard.string(forKey: "section.merged"),
                   let restored = AppSection(rawValue: raw) {
                    section = restored
                }
                // The owner column spans every org in the merged view, so load and
                // union all the real accounts' member directories at once.
                await directory.loadMerged(for: store.mergeableAccounts)
                await monitor.checkCurrentAccount()
                monitor.start()
            } else if let account = store.currentAccount {
                if let raw = UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)"),
                   let restored = AppSection(rawValue: raw) {
                    section = restored
                }
                // Warm the list(s) not currently on screen right away — concurrently with
                // the directory and health checks rather than queued behind them — so the
                // first switch to Pads/Questions has data ready instead of a spinner.
                async let warmed: Void = prefetchInactiveSections(account: account, active: section)
                await directory.load(for: account)
                await monitor.checkCurrentAccount()
                monitor.start()
                await warmed
            }
        }
        .onChange(of: section) { _, newValue in
            let key = store.isMergedView ? "section.merged" : store.currentAccount.map { "section.\($0.id.uuidString)" }
            if let key { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
        }
        .onChange(of: store.currentAccountID) { _, _ in
            padSelection = nil
            questionSelection = nil
        }
        // Switching into or out of the combined view changes what the panes show, so
        // drop any stale selection from the previous mode.
        .onChange(of: store.isMergedView) { _, _ in
            padSelection = nil
            questionSelection = nil
        }
    }

    /// Fetches whichever lists aren't currently displayed and stores them in the
    /// shared caches (which also persist to disk). The visible section loads itself,
    /// so we skip it here to avoid a duplicate request.
    private func prefetchInactiveSections(account: Account, active: AppSection) async {
        guard account.isMock || !account.apiKey.isEmpty else { return }
        let client = account.makeClient()
        let id = account.id
        // Stream pages so the cache is warm from page 1 — the first switch shows the
        // top (most-recently-updated) pads immediately while the rest fill in behind it,
        // instead of waiting for every page of a large org to land.
        if active != .pads {
            var latest: [Pad] = []
            do {
                for try await snapshot in client.listPadsIncrementally() {
                    latest = snapshot
                    // Warm memory per page (cheap); persist the final list once below.
                    PadsCacheStore.shared.set(id, pads: snapshot, persist: false)
                }
                PadsCacheStore.shared.set(id, pads: latest)
            } catch {
                // Partial results still warm the UI; persist whatever arrived.
                if !latest.isEmpty { PadsCacheStore.shared.set(id, pads: latest) }
            }
        }
        if active != .questions, let questions = try? await client.listQuestions(sort: "updated_at,desc") {
            QuestionsCacheStore.shared.set(id, questions: questions)
        }
    }

    private var threeColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section)
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
                .toolbar(removing: .sidebarToggle)
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
            .navigationSplitViewColumnWidth(
                min: contentMinWidth,
                ideal: max(480, contentMinWidth),
                max: max(760, contentMinWidth)
            )
        } detail: {
            SectionDetail(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection
            )
            .navigationSplitViewColumnWidth(min: Self.detailMinWidth, ideal: 520)
            // Attach search to the *detail* (trailing-most) column rather than the
            // content column or the whole split. Its toolbar items land at the true
            // window-right, over the detail pane — the Finder position — so the
            // content/detail divider can never slide the list under it, and it stays
            // clear of each section's own customizable toolbar (`pads.toolbar` /
            // `questions.toolbar`). The text is routed to the visible section by
            // `activeSearch`; ⌘F focuses it via the published FindAction.
            .searchable(text: activeSearch, placement: .toolbar, prompt: searchPrompt)
            .searchFocused($searchFieldFocused)
            .focusedSceneValue(
                \.findAction,
                FindAction(id: section == .questions ? "questions" : "pads") {
                    searchFieldFocused = true
                }
            )
        }
    }

    private var twoColumnSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(section: $section)
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
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SectionContent(
                section: section,
                padSelection: $padSelection,
                questionSelection: $questionSelection,
                padSearch: $padSearch,
                questionSearch: $questionSearch
            )
        }
    }
}

/// Restart key for the per-session load task: the chosen account plus whether the
/// combined view is active, so the task re-runs when either changes.
struct SessionKey: Hashable {
    let accountID: UUID?
    let merged: Bool
}

#Preview { ContentView() }
