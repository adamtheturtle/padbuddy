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

    /// Drives the sidebar collapse/expand. Bound to the `NavigationSplitView` so
    /// the system's standard sidebar toggle (and ⌃⌘S) flips it, while the
    /// width-driven auto-collapse below shares the same state.
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

    /// The host window's hard minimum content width — a single honest floor pinned on
    /// the `NSWindow` (see ``WindowMinWidth``), because `.frame(minWidth:)` inside a
    /// `NavigationSplitView` doesn't reliably reach the window's `contentMinSize`, so
    /// without it the window can be dragged narrow enough to crush/overlap the panes.
    /// Pads/Questions floor at list + detail; single-pane sections (Organization,
    /// Quota) floor at their lone content pane. Keyed off the section, not the live
    /// column visibility, so it stays constant while the user drags — the width-driven
    /// sidebar collapse handles narrowing, and the window never collapses to a
    /// width-forced single column (see #293).
    private var windowMinWidth: CGFloat {
        sectionHasDetail ? collapsedFloor : Self.detailMinWidth
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

    /// The window/toolbar title, driven by the visible section so it reads like
    /// Mail's current-mailbox title ("Pads", "Questions", …) instead of falling
    /// back to the "CoderPad" scene name when nothing is selected.
    private var sectionTitle: String {
        switch section {
        case .pads: "Pads"
        case .questions: "Questions"
        case .organization: "Organization"
        case .quota: "Quota"
        }
    }

    /// The window subtitle, shown beside the title in the toolbar. In the combined
    /// view it flags that the section spans every account (the cue the per-pane
    /// "Across all accounts" title used to carry); empty otherwise so single-account
    /// sections show just the section name.
    private var sectionSubtitle: String {
        store.isMergedView ? "All accounts" : ""
    }

    /// The active section's result-count summary, bubbled up from the list views via
    /// `SectionCountKey` (e.g. "12 pads"). Pads/Questions report a count; the merged
    /// variants already name the account span, so they supersede the "All accounts"
    /// cue while empty-count sections (Organization, Quota) fall back to it.
    @State private var sectionCount = ""

    /// What actually shows beneath the title: the count when a section publishes one,
    /// otherwise the static section subtitle.
    private var displaySubtitle: String {
        sectionCount.isEmpty ? sectionSubtitle : sectionCount
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
            // Floor the layout at the active section's needs; the width-driven
            // auto-collapse hides the sidebar between here and `sidebarVisibleFloor`.
            .frame(minWidth: windowMinWidth)
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
            // Pin the floor on the host window itself, since `.frame(minWidth:)`
            // doesn't reliably reach the window's `contentMinSize` from inside a
            // NavigationSplitView. Keyed off the section (constant during a drag),
            // so it never crushes the panes and never forces a single column.
            .background(WindowMinWidth(width: windowMinWidth))
        }
        .onChange(of: containerWidth) { _, width in updateSidebarCollapse(for: width) }
        // A section change moves the threshold (three columns vs. two), so
        // re-evaluate against the width we already know.
        .onChange(of: section) { _, _ in
            updateSidebarCollapse(for: containerWidth)
        }
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
        // Warm the quota too, so the sidebar knows up front whether the plan is
        // unlimited (and hides the unreachable Quota page) without the user having to
        // open Quota or Organization first. See #306.
        if let quota = try? await client.quota() {
            QuotaCacheStore.shared.set(id, quota: quota)
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
        .navigationTitle(sectionTitle)
        .navigationSubtitle(displaySubtitle)
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
        .navigationTitle(sectionTitle)
        .navigationSubtitle(displaySubtitle)
    }
}

/// Restart key for the per-session load task: the chosen account plus whether the
/// combined view is active, so the task re-runs when either changes.
struct SessionKey: Hashable {
    let accountID: UUID?
    let merged: Bool
}

/// Pins the host window's minimum content width. SwiftUI's `.frame(minWidth:)`
/// doesn't reliably propagate from inside a `NavigationSplitView` to the window's
/// `contentMinSize`, so without this the split can be dragged narrow enough to
/// crush or overlap its columns. A single floor (set by the caller per section);
/// the sidebar's width-driven auto-collapse handles narrowing above it.
private struct WindowMinWidth: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView)
    }

    /// Deferred to the next runloop turn: at make/update time the view isn't in a
    /// window yet and the content size is still settling. The width is constant for
    /// a given section, so this only runs on section change — never mid-drag — which
    /// keeps the floor from ever lagging behind a live resize.
    private func apply(from view: NSView) {
        let target = width
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.contentMinSize.width != target {
                window.contentMinSize.width = target
            }
            // Raising the floor (e.g. switching to a section with a wider minimum)
            // doesn't resize an already-narrower window, so grow the content back out
            // to honor it. Only ever grows, never shrinks, so it can't fight a user
            // dragging narrower.
            if let content = window.contentView, content.frame.width < target {
                window.setContentSize(NSSize(width: target, height: content.frame.height))
            }
        }
    }
}

#Preview { ContentView() }
