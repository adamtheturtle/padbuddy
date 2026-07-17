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
    let copyName: () -> Void
    let showTests: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct ScreenTestAction: Equatable {
    let id: Int
    let status: String
    let copySummary: () -> Void
    let openWindow: () -> Void
    let resend: () -> Void
    let cancel: () -> Void
    let delete: () -> Void

    var canResendOrCancel: Bool {
        status == "waiting"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

struct ScreenInviteAction: Equatable {
    let id: Int
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
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
/// pasteboard as plain text. `onCopyCommand` only fires while the list itself is
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

        // NSItemProvider needs an NSItemProviderWriting; String isn't one, but NSString is.
        // swiftlint:disable:next legacy_objc_type
        return [NSItemProvider(object: urlString as NSString)]
    }
}

#if os(macOS)
    func multiLinkPasteboardItem(_ urls: [String]) -> NSPasteboardItem? {
        let links = urls.filter { !$0.isEmpty }
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
        lhs.id == rhs.id
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
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
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
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.collapsed == rhs.collapsed
    }
}

extension FocusedValues {
    @Entry var sidebarToggleAction: SidebarToggleAction?
}
