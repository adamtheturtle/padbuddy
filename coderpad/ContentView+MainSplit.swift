//
//  ContentView+MainSplit.swift
//  coderpad
//

import AppKit
import SwiftUI

// MARK: - Split into small structs to reduce body type complexity

struct MainSplit: View {
    @State var store = AccountsStore.shared
    @State var network = NetworkMonitor.shared
    @Binding var section: AppSection
    let directory: OrgDirectory
    let monitor: AccountHealthMonitor

    @State var padSelection: Pad?
    @State var questionSelection: Question?

    /// The selection the *detail* pane renders, lagged a touch behind the live
    /// `padSelection`/`questionSelection`. The detail view is rebuilt from scratch
    /// per row (`PadDetailView(...).id(pad.id)` kicks off a fresh load), so driving
    /// it straight from the live selection rebuilds it on every keystroke while
    /// arrowing through the list — janking even the selection highlight, which
    /// SwiftUI paints in the same pass. The list's own highlight tracks the live
    /// selection and stays instant; the detail catches up the moment the user
    /// settles on a row (see `settleDetail*`). #326.
    @State var detailPad: Pad?
    @State var detailQuestion: Question?

    /// How long the detail pane waits for the selection to settle before rebuilding,
    /// when the change is part of a rapid arrow-key sweep. Long enough to skip the
    /// intermediate rows, short enough to feel immediate when the sweep stops.
    static let detailSettle = Duration.milliseconds(110)

    /// The same window in seconds, used to tell a rapid sweep from a deliberate click
    /// by the gap between consecutive selection changes (#395).
    static let detailSettleSeconds: TimeInterval = 0.110

    /// When the previous selection change landed, so the next change can be classified
    /// as part of a sweep (debounce) or a deliberate move (apply at once). See #395.
    @State var lastDetailChange: Date?

    // Caches observed so a selection saved last session can be restored once the list
    // (warmed from disk on first read) has the matching row. See #273.
    @State var padsCache = PadsCacheStore.shared
    @State var questionsCache = QuestionsCacheStore.shared

    /// Sections whose saved selection we've already restored this session, so a restore
    /// runs at most once per section and never re-asserts a row the user has since
    /// cleared. Reset when the account or combined-view mode changes.
    @State var restoredSections: Set<AppSection> = []

    /// The list search text, lifted out of `PadsView`/`QuestionsView` so the
    /// `.searchable` field can attach to the `NavigationSplitView` itself. That
    /// places it at the trailing edge of the *window* toolbar (over the detail
    /// pane, Finder-style) instead of the content column — where the content/detail
    /// divider used to slide the list under it. Each section keeps its own text; the
    /// active one is routed to the single searchable field via ``activeSearch``.
    @State var padSearch = ""
    @State var questionSearch = ""
    @State var screenSearch = ""

    /// Drives the lifted searchable field's focus so ⌘F (via ``FindAction``) can
    /// still jump straight into it from anywhere in the window.
    @FocusState var searchFieldFocused: Bool

    /// Routes the single window-toolbar search field to the visible section's text.
    /// Only `threeColumnSplit` (Pads/Questions) carries the field, so the default
    /// arm simply covers Pads.
    var activeSearch: Binding<String> {
        switch section {
        case .questions: $questionSearch
        case .screen: $screenSearch
        default: $padSearch
        }
    }

    var searchPrompt: Text {
        // Each branch must be its own `Text` literal so SwiftUI localizes it; a
        // `Text(ternary-of-Strings)` would use the verbatim initializer (#111).
        switch section {
        case .questions: Text("Search questions")
        case .screen: Text("Search campaigns")
        default: Text("Search pads")
        }
    }

    /// Drives the sidebar collapse/expand. Bound to the `NavigationSplitView` so
    /// the system's standard sidebar toggle (and ⌃⌘S) flips it, while the
    /// width-driven auto-collapse below shares the same state.
    @State var columnVisibility: NavigationSplitViewVisibility = .all

    /// Whether the sidebar's current collapse was driven by the window becoming too
    /// narrow rather than a manual toggle. We only auto-expand what we auto-collapsed,
    /// so a deliberate choice is never overridden by a resize.
    @State var autoCollapsed = false

    /// Set when the user deliberately reopens the sidebar while the window is too
    /// narrow to hold every column (e.g. macOS split-screen on a small display).
    /// Without it, the next width observation re-collapses the sidebar the instant the
    /// user expands it — the toggle appears to "not come in fully" because the
    /// auto-collapse interrupts the expand animation (#307). While set, the width-driven
    /// collapse stands down until the window grows wide again or the user closes the
    /// sidebar themselves.
    @State var keepSidebarWhileNarrow = false

    /// Latest observed width of the split-view container, kept so a section change
    /// (which moves the collapse threshold) can be re-evaluated without waiting for
    /// the next resize.
    @State var containerWidth: CGFloat = 0

    /// Gates the once-per-launch restore of the saved sidebar collapse state (#273),
    /// so reasserting it never fights a manual toggle made later in the session.
    @State var didRestoreSidebar = false

    /// UserDefaults key for the user's deliberate sidebar collapse choice, resumed on
    /// the next launch (#273). A window-layout preference, so it's global rather than
    /// per-account like the selection/filter state.
    static let sidebarCollapsedKey = "sidebar.collapsed"

    /// Floor for the content column: the natural width of the active section's
    /// filter bar, so it can never be dragged too thin to hold all filters.
    @State var contentMinWidth: CGFloat = 380

    /// Floor for the sidebar column, derived at runtime from the widest row label
    /// (see ``SidebarRowWidthKey``) plus the row's fixed chrome, so the longest
    /// label never wraps or truncates regardless of font or label changes.
    @State var sidebarMinWidth: CGFloat = 220

    /// Non-text width of a sidebar row: the VStack + row horizontal insets, the
    /// icon column and its spacing, and trailing breathing room before the
    /// selection pill's edge. Added to the measured label width.
    static let sidebarRowChrome: CGFloat = 110

    /// Minimum width of the detail column. A single source shared by the column
    /// definition and the auto-collapse/window-floor math, so they can't drift.
    static let detailMinWidth: CGFloat = 360

    /// Relaxed column minimum used for the content and detail columns while the user
    /// is deliberately keeping the sidebar open in a window too narrow to hold every
    /// column at its normal floor (#307). With the normal floors in force the sidebar
    /// can't slide fully open — content (380) + detail (360) already claim more than a
    /// split-screen tile leaves once the sidebar wants its ~220 — so AppKit reveals the
    /// sidebar only partway ("doesn't come in fully"). Dropping the other columns'
    /// floors here lets the sidebar open completely; the panes get cramped, which is
    /// the tradeoff the user opted into by reopening the sidebar in a narrow window.
    static let narrowOverrideColumnMin: CGFloat = 200

    /// Ceiling for ``contentMinWidth``. The filter bar reports its full natural
    /// width, which can exceed the budget the window's own minimum width leaves
    /// for this column once the sidebar and detail minimums are subtracted. Left
    /// uncapped, shrinking the window inflates this floor past that budget and the
    /// list pane gets clipped instead of the filter bar simply scrolling. Holding
    /// the floor here keeps sidebar + content + detail within the window minimum.
    static let contentMinWidthCeiling: CGFloat = 380

    /// Hard floor for ``contentMinWidth``. The search field itself now lives on the
    /// split view (trailing window toolbar, over the detail pane) rather than this
    /// column, but a baseline keeps the list readable: a section whose filter bar
    /// measures narrower than this shouldn't collapse to a sliver. Kept below the
    /// ceiling so the adaptive filter-bar narrowing still applies in the band above.
    static let contentSearchMinWidth: CGFloat = 340

    /// Pads and Questions drive a detail pane; Organization and Quota are
    /// single-pane sections, so they drop the third column entirely.
    var sectionHasDetail: Bool {
        switch section {
        case .pads, .questions, .screen: true
        case .organization, .quota: false
        }
    }

    /// UserDefaults key for the user's "hide the detail pane" choice, shared with the
    /// View ▸ Hide Detail Pane menu command (#394). A window-layout preference, so it's
    /// global rather than per-account.
    static let detailPaneHiddenKey = "detail.pane.hidden"

    /// When set, Pads/Questions drop their detail (third) column too, so the window can
    /// be made very thin — just the sidebar and the list (#394). Toggled from the View
    /// menu; persisted so the layout is restored next launch.
    @AppStorage(Self.detailPaneHiddenKey) var detailPaneHidden = false

    /// Whether the detail column should be shown for the current section: only the
    /// list-backed sections have one, and only when the user hasn't hidden it.
    var showsDetailColumn: Bool {
        sectionHasDetail && !detailPaneHidden
    }

    /// The window/toolbar title, driven by the visible section so it reads like
    /// Mail's current-mailbox title ("Pads", "Questions", …) instead of falling
    /// back to the "CoderPad" scene name when nothing is selected.
    var sectionTitle: String {
        switch section {
        case .pads: String(localized: "Pads")
        case .questions: String(localized: "Questions")
        case .organization: String(localized: "Organization")
        case .quota: String(localized: "Quota")
        case .screen: String(localized: "Screen")
        }
    }

    /// The window subtitle, shown beside the title in the toolbar. In the combined
    /// view it flags that the section spans every account (the cue the per-pane
    /// "Across all accounts" title used to carry); empty otherwise so single-account
    /// sections show just the section name.
    private var sectionSubtitle: String {
        store.isMergedView ? String(localized: "All accounts") : ""
    }

    /// The active section's result-count summary, bubbled up from the list views via
    /// `SectionCountKey` (e.g. "12 pads"). Pads/Questions report a count; the merged
    /// variants already name the account span, so they supersede the "All accounts"
    /// cue while empty-count sections (Organization, Quota) fall back to it.
    @State var sectionCount = ""

    /// What actually shows beneath the title: the count when a section publishes one,
    /// otherwise the static section subtitle.
    var displaySubtitle: String {
        sectionCount.isEmpty ? sectionSubtitle : sectionCount
    }

    var body: some View {
        VStack(spacing: 0) {
            // Offline takes precedence: when there's no path to CoderPad nothing can
            // be edited regardless of the key, so show the offline banner and skip the
            // (now moot) unauthorized one (#321).
            if network.isOffline {
                OfflineBanner()
            } else if !store.isMergedView, let id = store.currentAccountID, monitor.isUnauthorized(id) {
                // In the combined view, per-account fetch failures surface inline in the
                // merged list, so the single-account unauthorized banner is suppressed.
                UnauthorizedBanner(monitor: monitor)
            }
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
            .frame(minWidth: isBelowWindowFloor ? nil : windowMinWidth,
                   maxWidth: .infinity, alignment: .leading)
            // Pin the drag floor on the host window itself, since `.frame(minWidth:)`
            // alone doesn't reliably reach the window's `contentMinSize` from inside a
            // NavigationSplitView. This view also reports the window's *true* content
            // width back into `containerWidth` (driving the sidebar auto-collapse and the
            // below-floor detection): a SwiftUI reader here would only ever see the
            // floored frame width and never notice the OS squeezing the window narrower.
            .background(WindowMinWidth(width: windowMinWidth) { width in
                if containerWidth != width { containerWidth = width }
            })
            // Suppress AppKit's sidebar/content tracking-separator line while the
            // sidebar is collapsed — with no sidebar divider to track it draws a stray
            // vertical line right after the leading actions (#337).
            .background(SidebarSeparatorHider(collapsed: columnVisibility != .all))
            // Enable View ▸ Customize Toolbar… — SwiftUI leaves the merged window
            // toolbar's `allowsUserCustomization` off for this split + search setup,
            // disabling the menu item even though every toolbar is customizable (#408).
            .background(ToolbarCustomizationEnabler())
        }
        .onChange(of: containerWidth) { _, width in updateSidebarCollapse(for: width) }
        // Honor a deliberate reopen in a too-narrow window so the auto-collapse doesn't
        // fight the toggle (#307), and remember a deliberate collapse for next launch (#273).
        .onChange(of: columnVisibility) { _, visibility in
            handleVisibilityChange(to: visibility)
            persistSidebarCollapsed(visibility)
        }
        // A section change moves the threshold (three columns vs. two), so
        // re-evaluate against the width we already know.
        .onChange(of: section) { _, _ in
            updateSidebarCollapse(for: containerWidth)
        }
        .task(id: SessionKey(accountID: store.currentAccountID, merged: store.isMergedView)) {
            if store.isMergedView {
                if let raw = UserDefaults.standard.string(forKey: "section.merged"),
                   let restored = AppSection(rawValue: raw), restored != .screen {
                    // Screen is per-account, so it never applies in the combined view (#432).
                    section = restored
                }
                // Section is settled, so the collapse can map to the right column count.
                restoreSidebarCollapsedIfNeeded()
                // The owner column spans every org in the merged view, so load and
                // union all the real accounts' member directories at once.
                await directory.loadMerged(for: store.mergeableAccounts)
                await monitor.checkCurrentAccount()
                monitor.start()
            } else if let account = store.currentAccount {
                if let raw = UserDefaults.standard.string(forKey: "section.\(account.id.uuidString)"),
                   let restored = AppSection(rawValue: raw),
                   restored != .screen || account.makeScreenClient() != nil {
                    // Don't land on Screen if the account no longer has a Screen key (#432).
                    section = restored
                }
                // Section is settled, so the collapse can map to the right column count.
                restoreSidebarCollapsedIfNeeded()
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
            restoredSections.removeAll()
        }
        // Switching into or out of the combined view changes what the panes show, so
        // drop any stale selection from the previous mode.
        .onChange(of: store.isMergedView) { _, _ in
            padSelection = nil
            questionSelection = nil
            restoredSections.removeAll()
        }
        // Resume the row the user left selected last session, once its list has loaded
        // (#273). Re-runs when the section is restored at launch and when rows arrive.
        .onChange(of: restoreProbe, initial: true) { _, _ in restoreSelectionIfNeeded() }
        .onChange(of: padSelection) { _, sel in persistSelection(padID: sel?.id, questionID: nil) }
        .onChange(of: questionSelection) { _, sel in persistSelection(padID: nil, questionID: sel?.id) }
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

/// An opt-in toolbar button that hides or shows the detail (third) pane (#404).
/// Hidden by default in the customizable toolbar — the View ▸ Hide Detail Pane
/// menu item (⌃⌘D, #394) is the primary control — but available to drag in via
/// Customize Toolbar for users who flip to the thin two-column layout often. Lives
/// in the always-present list-column toolbars (Pads/Questions, single and merged),
/// not the detail toolbar, so "Show" is still reachable once the pane is hidden.
/// Reads the same `@AppStorage` key the menu command and layout share, so all three
/// stay in lockstep, and animates the swap like the sidebar toggle (#403).
struct DetailPaneToggleToolbarContent: CustomizableToolbarContent {
    @AppStorage(MainSplit.detailPaneHiddenKey) private var detailPaneHidden = false

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "toggle-detail-pane", placement: .automatic) {
            Button {
                withAnimation(.smooth) { detailPaneHidden.toggle() }
            } label: {
                Label(detailPaneHidden ? "Show Detail Pane" : "Hide Detail Pane",
                      systemImage: "sidebar.right")
            }
            .help(detailPaneHidden ? "Show the detail pane" : "Hide the detail pane")
        }
        .defaultCustomization(.hidden)
    }
}

#Preview { ContentView() }
