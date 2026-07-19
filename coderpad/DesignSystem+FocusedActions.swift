//
//  DesignSystem+FocusedActions.swift
//  coderpad
//
//  Focused scene values and list copy/link helpers that let window-level menu
//  commands act on the frontmost window's selection. Split out of
//  `DesignSystem+Org.swift` to keep each file under the length limit.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

// MARK: - Focused scene value for the selected pad

extension FocusedValues {
    /// The pad selected in the active window's list, published via
    /// `focusedSceneValue` so the Pad menu commands can act on it whenever the
    /// window is frontmost — independent of which subview holds keyboard focus.
    @Entry var focusedPad: Pad?
    /// The account owning `focusedPad`, published alongside it so menu commands
    /// can target the right account when slugs collide (#1820-#1824).
    @Entry var focusedPadAccountID: UUID?
}

extension FocusedValues {
    /// Whether the selected pad is a favorite of the current account, published
    /// by `PadDetailView` so the Pad menu's Favorite command can show the
    /// matching "Add to"/"Remove from Favorites" title.
    @Entry var focusedPadIsFavorite: Bool?
}

extension FocusedValues {
    /// The question selected in the active window's list, published via
    /// `focusedSceneValue` so the Question menu commands can act on it whenever the
    /// window is frontmost — the Questions-pane counterpart to `focusedPad`.
    @Entry var focusedQuestion: Question?
    /// The account owning `focusedQuestion` (#1816-#1819).
    @Entry var focusedQuestionAccountID: UUID?
}

extension FocusedValues {
    /// Whether the selected question is a favorite of the current account,
    /// published by `QuestionDetailView` so the Question menu's Favorite command
    /// can show the matching "Add to"/"Remove from Favorites" title.
    @Entry var focusedQuestionIsFavorite: Bool?
}

extension FocusedValues {
    /// The selected question's web URL, published by `QuestionDetailView` so the
    /// Question menu's Share/Copy URL commands can act on it. Built from the
    /// account's server URL there (the question model has no URL of its own), so
    /// the menu honors a custom CoderPad domain — the Pad menu's counterpart reads
    /// `focusedPad.webURL` directly because pads carry an absolute API URL.
    @Entry var focusedQuestionURL: URL?
}

// MARK: - Focused scene values for Screen commands

struct ScreenCampaignAction: Equatable {
    let id: String
    /// A hash of the content the closures captured (the campaign's name), so a
    /// refresh that keeps the id but changes the record re-publishes instead of
    /// deduplicating onto a closure holding the stale snapshot (#1707).
    var contentFingerprint: Int = 0
    let copyName: () -> Void
    let showTests: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.contentFingerprint == rhs.contentFingerprint
    }
}

struct ScreenTestAction: Equatable {
    let id: Int
    let status: String
    /// A hash of the content the closures captured, so a refreshed record with
    /// the same id/status re-publishes instead of keeping commands bound to the
    /// stale snapshot (#1708).
    var contentFingerprint: Int = 0
    let copySummary: () -> Void
    let openWindow: () -> Void
    let resend: () -> Void
    let cancel: () -> Void
    let delete: () -> Void

    var canResendOrCancel: Bool {
        status == "waiting"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.contentFingerprint == rhs.contentFingerprint
    }
}

struct ScreenInviteAction: Equatable {
    let id: Int
    /// Account and campaign content are part of the captured invitation target.
    /// Re-publish when either changes even if the server-local campaign id is reused.
    var accountID: UUID?
    var contentFingerprint: Int = 0
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.accountID == rhs.accountID
            && lhs.contentFingerprint == rhs.contentFingerprint
    }
}

extension FocusedValues {
    @Entry var focusedScreenCampaignAction: ScreenCampaignAction?
    @Entry var focusedScreenTestAction: ScreenTestAction?
    @Entry var focusedScreenInviteAction: ScreenInviteAction?
}

// MARK: - Copy command for list selections

/// Builds the optional action for `View.onCopyCommand` from the selected row's
/// link. Returns `nil` when there's no selection, so the standard Edit ▸ Copy
/// item (and ⌘C) greys out; otherwise a closure that places `urlString` on the
/// pasteboard as both a URL and plain text. `onCopyCommand` only fires while the list itself is
/// the first responder, so this never steals ⌘C from a focused text field. Shared
/// by every pad and question list so a selected row copies its link, the standard
/// macOS list-copy behavior users reach for to paste into Slack, mail, or an event.
func copyLinkCommand(hasSelection: Bool,
                     urls makeURLString: @escaping () -> String) -> (() -> [NSItemProvider])? {
    // `hasSelection` is the O(1) gate (an empty selection set), so returning nil to
    // disable Edit ▸ Copy costs nothing on the render path. The link string itself —
    // an O(N) scan over the filtered list to resolve the selected rows — is built
    // lazily inside the returned closure, so it runs only when the user actually
    // copies, not on every body pass that constructs this modifier. Evaluating it
    // eagerly here is what added an O(N) scan to each selection-driven render and made
    // clicking through a large list lag.
    guard hasSelection else { return nil }

    return {
        let urlString = makeURLString()
        guard !urlString.isEmpty else { return [] }

        // Publish the rich URL representation expected by link-aware destinations,
        // while retaining text for terminals and other plain-text consumers (#2738).
        guard let url = URL(string: urlString) else {
            // swiftlint:disable:next legacy_objc_type
            return [NSItemProvider(object: urlString as NSString)]
        }

        // swiftlint:disable:next legacy_objc_type
        let provider = NSItemProvider(object: url as NSURL)
        // swiftlint:disable:next legacy_objc_type
        provider.registerObject(urlString as NSString, visibility: .all)
        return [provider]
    }
}

#if os(macOS)
    func multiLinkPasteboardItem(_ urls: [String]) -> NSPasteboardItem? {
        var seen = Set<String>()
        let links = urls.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !links.isEmpty else { return nil }

        let item = NSPasteboardItem()
        if let first = links.first {
            item.setString(first, forType: .URL)
        }
        item.setString(links.joined(separator: "\n"), forType: .string)
        return item
    }
#endif

/// Action published by whichever pane currently owns a search field, so the
/// global ⌘F command can focus it. Panes set this via `focusedSceneValue` while
/// visible; the command reads it both to perform the find and to know whether
/// Find applies in the current context (it's disabled when no pane provides one).
///
/// `Equatable` on a stable per-pane `id` is load-bearing: the wrapped closure
/// can't be compared, so without it every body pass re-publishes a "new" value
/// for the same scene key. Because `NavigationSplitView` re-evaluates its panes
/// several times per layout pass, SwiftUI flags those redundant writes as
/// "FocusedValue update tried to update multiple times per frame." Comparing by
/// `id` lets SwiftUI dedupe the identical re-assignments instead.
struct FindAction: Equatable {
    /// Identifies the owning pane (e.g. "pads"), so re-publishes from the same
    /// pane compare equal while a genuine pane switch compares unequal.
    let id: String
    /// Stable for one mounted publisher, but changes when SwiftUI replaces the
    /// owning search view. This prevents equality from retaining its old closure.
    let publisherID: UUID
    /// `true` when this pane's search is a SwiftUI `.searchable` field, which on
    /// iOS already installs its own ⌘F "Find" key command. `IPadCommands` reads
    /// this to avoid registering a second ⌘F over it (a duplicate UIKit logs as a
    /// `_UIMenuBuilderError`). Panes with a bespoke filter field (e.g. Organization)
    /// leave it `false` so the iPad command still provides their ⌘F. Unused on
    /// macOS, where `.searchable` does not bind ⌘F and the menu command always wins.
    var hasSystemFindShortcut: Bool = false
    /// Declared last so call sites can pass it as a trailing closure.
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        // The shortcut capability participates: a pane that keeps its id but
        // changes whether it installs its own ⌘F must read as a change, or the
        // iPad command registration stays in the wrong state (#1706).
        lhs.id == rhs.id && lhs.publisherID == rhs.publisherID
            && lhs.hasSystemFindShortcut == rhs.hasSystemFindShortcut
    }
}

extension FocusedValues {
    @Entry var findAction: FindAction?
}

extension FocusedValues {
    /// Whether the frontmost window's content is read-only (the app is offline),
    /// published by `ContentView` so the Pad/Question menu commands can disable their
    /// mutating items to match the in-window controls. `nil` when no window publishes
    /// it (treated as editable). The view-tree counterpart is `EnvironmentValues.isReadOnly`.
    @Entry var isReadOnly: Bool?
}

/// Action published by whichever detail pane can be printed, so the File menu's
/// ⌘P command can render it through the standard print panel. Like `FindAction`,
/// it's `Equatable` on a stable per-content `id` so re-publishes from the same
/// content dedupe instead of tripping SwiftUI's multiple-updates-per-frame
/// warning during `NavigationSplitView`'s repeated layout passes. The command
/// reads it both to perform the print and to disable itself when nothing focused
/// is printable.
struct PrintAction: Equatable {
    /// Identifies the printable content (e.g. "question-42"), so re-publishes for
    /// the same content compare equal while a genuine selection change differs.
    let id: String
    /// A hash of the content the closure captured, so an update that keeps the
    /// same pad/question id still re-publishes — otherwise ⌘P could render the
    /// earlier snapshot the deduplicated closure holds (#1710).
    var contentFingerprint: Int = 0
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.contentFingerprint == rhs.contentFingerprint
    }
}

extension FocusedValues {
    @Entry var printAction: PrintAction?
}

/// Action published by the main split so the View ▸ Show/Hide Sidebar command can
/// flip the sidebar through the same `columnVisibility` state the toolbar toggle
/// drives — keeping the menu item, its ⌃⌘S shortcut, and the toolbar button all in
/// lockstep. Routing through this rather than AppKit's `toggleSidebar:` selector
/// means our collapse-persistence (#273) and width auto-collapse (#307) handlers
/// still run. `Equatable` on `collapsed` dedupes the repeated re-publishes
/// `NavigationSplitView`'s layout passes trigger, like `FindAction`. (#396)
struct SidebarToggleAction: Equatable {
    /// Whether the sidebar is currently collapsed, so the menu item can read
    /// "Show Sidebar" vs "Hide Sidebar".
    let collapsed: Bool
    /// Identifies the publishing split *instance* (the caller passes a stable
    /// per-identity `@State` UUID): comparing `collapsed` alone let a rebuilt
    /// split with the same visible state deduplicate onto a closure tied to the
    /// old instance's detached state, leaving the View menu toggling nothing
    /// (#1709).
    let instanceToken: UUID
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.collapsed == rhs.collapsed && lhs.instanceToken == rhs.instanceToken
    }
}

/// Action published by the main split so the View ▸ Hide Detail Pane command and the
/// toolbar button flip *this window's* detail column.
///
/// The visibility used to be one `@AppStorage` flag, so hiding the detail pane in a
/// narrow window or an iPad scene re-laid-out every other window too, with no way to
/// override it per scene (#2301) — and the control toggled that global flag even in
/// sections that have no detail column at all, changing a hidden preference with no
/// visible feedback (#2302). Publishing it as a focused action follows
/// `SidebarToggleAction`: the frontmost window owns the state, and the command
/// disables itself when there is nothing to toggle.
struct DetailPaneToggleAction: Equatable {
    /// Whether this window's detail pane is currently hidden, so the control can read
    /// "Show" vs "Hide".
    let hidden: Bool
    /// Identifies the publishing split instance, for the same reason
    /// `SidebarToggleAction` carries one (#1709).
    let instanceToken: UUID
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hidden == rhs.hidden && lhs.instanceToken == rhs.instanceToken
    }
}

extension FocusedValues {
    @Entry var sidebarToggleAction: SidebarToggleAction?
    /// Nil when the visible section has no detail column, which disables the control
    /// rather than letting it toggle something invisible (#2302).
    @Entry var detailPaneToggleAction: DetailPaneToggleAction?
}
