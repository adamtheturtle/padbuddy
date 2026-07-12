//
//  ContentView+MainSplit.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import SwiftUI

// MARK: - Split into small structs to reduce body type complexity

struct MainSplit: View {
    @State var store = AccountsStore.shared
    @State var network = NetworkMonitor.shared
    /// Honors the Reduce Motion accessibility setting (#614): when on, the sidebar
    /// and detail-pane layout transitions snap instead of sliding. Read in the
    /// `withAnimation` sites in `ContentView+SplitSidebar`.
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    /// Observed so the Screen section's title/search prompt can reflect whether a
    /// campaign is drilled into (campaigns → candidates), see #467/#468/#470.
    @State var nav = AppNavigation.shared
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
        // The single window field is shared by the campaigns list and a drilled-into
        // campaign's candidate list, so name what it actually searches now (#470).
        case .screen:
            if nav.screenCampaignSelection == nil { Text("Search campaigns") } else { Text("Search candidates") }
        default: Text("Search pads")
        }
    }

    /// Drives the sidebar collapse/expand. Bound to the `NavigationSplitView` so
    /// the system's standard sidebar toggle (and ⌃⌘S) flips it, while the
    /// width-driven auto-collapse below shares the same state.
    @State var columnVisibility: NavigationSplitViewVisibility = .all

    /// Chooses the visible column when the split collapses into one column on iPhone.
    /// Section changes move forward to the list/content column; row selections move
    /// forward to detail, matching the regular-width split's hierarchy.
    @State var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

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

    // Fixed width of the iPad sidebar column. iPad gets no `navigationSplitViewColumnWidth`
    // from `macColumnWidth` (the #599 fix), so this single value pins the leftmost column
    // so it doesn't jump width as the split swaps between its two- and three-column forms.
    // Matches the standard iOS regular-width sidebar size and the macOS ideal.
    #if os(iOS)
        static let iPadSidebarWidth: CGFloat = 320
    #endif

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
    /// back to the "PadBuddy" scene name when nothing is selected.
    var sectionTitle: String {
        switch section {
        case .pads: String(localized: "Pads")
        case .questions: String(localized: "Questions")
        case .organization: String(localized: "Organization")
        case .quota: String(localized: "Quota")
        // The Screen section's content column is the campaigns list (a drilled-into
        // campaign's tests view supplies its own title), so name it "Campaigns" (#468).
        case .screen: String(localized: "Campaigns")
        }
    }

    /// The window subtitle, shown beside the title in the toolbar. In the combined
    /// view it flags that the section spans every account (the cue the per-pane
    /// "Across all accounts" title used to carry); empty otherwise so single-account
    /// sections show just the section name.
    private var sectionSubtitle: String {
        store.isMergedView ? String(localized: "All accounts") : ""
    }

    /// What actually shows beneath the title: the active list section's result-count
    /// summary (e.g. "12 pads") when it publishes one, otherwise the static section
    /// subtitle. The count is published by the list panes into
    /// ``AppNavigation/sectionCountSubtitle`` (via `reportsSectionCount`) rather than a
    /// SwiftUI preference, which faulted when a count changed across a single frame's
    /// body passes. Pads/Questions report a count; the merged variants already name the
    /// account span, so their count supersedes the "All accounts" cue while empty-count
    /// sections (Organization, Quota) fall back to it. A count published for a different
    /// section is ignored: when switching sections the outgoing count outlives the change
    /// until the new pane republishes, and showing it under the new title reads as a flash.
    var displaySubtitle: String {
        guard nav.sectionCountSection == section, !nav.sectionCountSubtitle.isEmpty else {
            return sectionSubtitle
        }

        return nav.sectionCountSubtitle
    }

    // `body` is split across `splitLayout` + two observer groups rather than one long
    // chain: the VStack plus a ~13-modifier observer chain makes the Swift type-checker
    // infer a single deeply-nested generic type and blows the Release build's 250ms
    // type-check-timing budget (warnings-as-errors). Each piece type-checks
    // independently. Order is preserved. (#427)
    var body: some View {
        decoratedSelection
    }

    // `splitLayout`, `decoratedObservers`, and `decoratedSelection` live in
    // ContentView+MainSplit+Layout.swift (split out for file length).
}

/// Construct `ContentView` inside a dedicated host rather than directly in the
/// `#Preview` closure. As one expression, `#Preview { ContentView() }` sits right on
/// the 250ms `-warn-long-expression-type-checking` budget under the Release build's
/// whole-module type-checking and flakily trips warnings-as-errors. Splitting it lets
/// the `#Preview` closure type-check a bare `init` while `ContentView()` is checked in
/// this view's own `body` in isolation, keeping both well under budget. (#427)
private struct ContentViewPreviewHost: View {
    var body: some View {
        ContentView()
    }
}

#Preview { ContentViewPreviewHost() }
