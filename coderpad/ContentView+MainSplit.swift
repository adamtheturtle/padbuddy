//
//  ContentView+MainSplit.swift
//  coderpad
//

import SwiftUI

// MARK: - Split into small structs to reduce body type complexity

struct MainSplit: View {
    @State private var store = AccountsStore.shared
    @Binding var section: AppSection
    let directory: OrgDirectory
    let monitor: AccountHealthMonitor

    @State private var padSelection: Pad?
    @State private var questionSelection: Question?

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

    /// Hard floor for ``contentMinWidth``. The list's search now lives in the window
    /// toolbar (`.searchable(.toolbar)`), which renders a fixed-width field of about
    /// this size. Without this floor a section whose filter bar measures narrower
    /// would let the list column be dragged thinner than its own search field — the
    /// list ending up visibly narrower than the search bar above it. Kept below the
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
            if let id = store.currentAccountID, monitor.isUnauthorized(id) {
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
        .task(id: store.currentAccountID) {
            if let account = store.currentAccount {
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
            if let account = store.currentAccount {
                UserDefaults.standard.set(newValue.rawValue,
                                          forKey: "section.\(account.id.uuidString)")
            }
        }
        .onChange(of: store.currentAccountID) { _, _ in
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
                questionSelection: $questionSelection
            )
            // Round to whole points and only assign on a real change. The measured
            // filter-bar width feeds this column's own min width, so re-writing it
            // with sub-pixel-different (or identical) values would re-invalidate the
            // column mid-layout — which AppKit reports as layout recursion.
            .onPreferenceChange(FilterBarWidthKey.self) { width in
                // Clamp to the ceiling so the column floor never demands more than
                // the window's minimum width can give it. Past this the filter bar
                // scrolls horizontally rather than squeezing and clipping the list.
                // Floor it at the toolbar search width so the list can never be
                // dragged thinner than its own search field.
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
                questionSelection: $questionSelection
            )
        }
    }
}

private struct SectionContent: View {
    @State private var store = AccountsStore.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?

    var body: some View {
        if let account = store.currentAccount {
            let client = account.makeClient()
            switch section {
            case .pads: PadsView(client: client, selection: $padSelection).id(account.id)
            case .questions: QuestionsView(client: client, selection: $questionSelection).id(account.id)
            case .organization: OrganizationView(client: client).id(account.id)
            case .quota: QuotaView(client: client).id(account.id)
            }
        }
    }
}

private struct SectionDetail: View {
    @State private var store = AccountsStore.shared
    let section: AppSection
    @Binding var padSelection: Pad?
    @Binding var questionSelection: Question?

    var body: some View {
        if let account = store.currentAccount {
            let client = account.makeClient()
            switch section {
            case .pads:
                if let pad = padSelection {
                    PadDetailView(client: client, pad: pad).id(pad.id)
                } else {
                    ContentUnavailableView("Select a pad", systemImage: "doc.text")
                }
            case .questions:
                if let question = questionSelection {
                    QuestionDetailView(client: client, question: question).id(question.id)
                } else {
                    ContentUnavailableView("Select a question", systemImage: "questionmark.bubble")
                }
            case .organization, .quota:
                ContentUnavailableView("Nothing selected", systemImage: "sidebar.squares.leading",
                                       description: Text("This section shows everything in the list."))
            }
        }
    }
}

#Preview { ContentView() }
