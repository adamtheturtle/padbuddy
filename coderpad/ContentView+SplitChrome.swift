//
//  ContentView+SplitChrome.swift
//  coderpad
//

import AppKit
import SwiftUI

/// Restart key for the per-session load task: the chosen account plus whether the
/// combined view is active, so the task re-runs when either changes.
struct SessionKey: Hashable {
    let accountID: UUID?
    let merged: Bool
}

/// Pins the host window's minimum content width and reports the window's *true*
/// content width back to SwiftUI. SwiftUI's `.frame(minWidth:)` doesn't reliably
/// propagate from inside a `NavigationSplitView` to the window's `contentMinSize`,
/// so without the floor here the split can be dragged narrow enough to crush or
/// overlap its columns. The width report exists because the OS (Split View, tiling,
/// Stage Manager) can shrink a window *below* `contentMinSize`, and SwiftUI's own
/// width readers sit inside the floored frame — so only a value read straight off
/// the `NSWindow` reveals how narrow the window has actually become.
struct WindowMinWidth: NSViewRepresentable {
    let width: CGFloat
    /// Reports the window's current content width (the live `NSWindow` value, not the
    /// floored SwiftUI frame). Called on attach and on every window resize.
    let onContentWidth: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    /// Deferred to the next runloop turn: at make/update time the view isn't in a
    /// window yet and the content size is still settling. Always (re)attaches the resize
    /// observer, reports the current width, and pins `contentMinSize` (cheap, and during
    /// an OS tile it just sets a constraint the OS ignores rather than resizing — so it
    /// keeps the drag floor honest for when the tile ends). Only the *grow* is gated to
    /// an actual floor change (a section switch): the closure prop makes `updateNSView`
    /// fire on every render, and growing on a resize-driven update would yank a
    /// just-narrowed (OS-tiled) window straight back to the floor, fighting the tile.
    private func apply(from view: NSView, coordinator: Coordinator) {
        let target = width
        let report = onContentWidth
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            coordinator.observe(window, report: report)
            coordinator.report()
            if window.contentMinSize.width != target {
                window.contentMinSize.width = target
            }
            // Raising the floor (e.g. switching to a section with a wider minimum)
            // doesn't resize an already-narrower window, so grow the content back out
            // to honor it — but only on the floor change itself, never on a resize-driven
            // re-render. Only ever grows, never shrinks, so it can't fight a user drag.
            guard coordinator.applyFloorIfNeeded(target) else { return }

            if let content = window.contentView, content.frame.width < target {
                window.setContentSize(NSSize(width: target, height: content.frame.height))
            }
        }
    }

    /// Observes the host window's resizes and forwards its content width. The window
    /// emits `didResizeNotification` for OS-driven squeezes (tiling/Split View) the
    /// same as for user drags, so this catches the narrowing that `contentMinSize`
    /// can't prevent.
    final class Coordinator {
        private weak var window: NSWindow?
        private var forward: ((CGFloat) -> Void)?
        private var observer: (any NSObjectProtocol)?
        private var appliedTarget: CGFloat?

        /// Returns true (and records the value) only when `target` differs from the
        /// last-applied floor, so the caller pins `contentMinSize`/grows the window on a
        /// section switch but not on the frequent closure-driven re-renders.
        func applyFloorIfNeeded(_ target: CGFloat) -> Bool {
            guard appliedTarget != target else { return false }

            appliedTarget = target
            return true
        }

        func observe(_ window: NSWindow, report: @escaping (CGFloat) -> Void) {
            forward = report
            guard self.window !== window else { return }

            stopObserving()
            self.window = window
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // The observer runs on `.main`, so `report()` (which touches main-actor
                // AppKit window state) is safe to call synchronously — assert that
                // isolation rather than calling it from the nonisolated block (#420).
                MainActor.assumeIsolated { self?.report() }
            }
        }

        func report() {
            guard let width = window?.contentView?.frame.width else { return }

            forward?(width)
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            window = nil
        }
    }
}

/// Turns on user customization for the host window's toolbar so View ▸ Customize
/// Toolbar… is enabled (#408). Every section and detail toolbar is already a
/// customizable `.toolbar(id:)` with stable item ids, so the customization palette
/// works once it's allowed — but SwiftUI never flips `allowsUserCustomization` to
/// `true` on the merged window toolbar for this `NavigationSplitView` + `.searchable`
/// setup, which leaves `ToolbarCommands()`'s menu item permanently disabled. There's
/// no SwiftUI lever for the flag, so set it on the `NSToolbar` directly.
///
/// Mirrors `SidebarSeparatorHider`: deferred a runloop turn (the window/toolbar isn't
/// attached at make/update time) and re-enforced via `NSToolbar.willAddItemNotification`,
/// because SwiftUI rebuilds the toolbar whenever it swaps in the detail-pane items and a
/// one-shot set wouldn't survive that.
struct ToolbarCustomizationEnabler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    private func apply(from view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let toolbar = view.window?.toolbar else { return }

            coordinator.observe(toolbar)
            coordinator.enforce()
        }
    }

    final class Coordinator {
        private weak var toolbar: NSToolbar?
        private var observer: (any NSObjectProtocol)?

        /// Re-enable customization whenever SwiftUI rebuilds the toolbar (it re-adds
        /// items on every selection-driven detail swap). Idempotent per toolbar.
        func observe(_ toolbar: NSToolbar) {
            guard self.toolbar !== toolbar else { return }

            stopObserving()
            self.toolbar = toolbar
            observer = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self] _ in
                // Deferred a runloop turn: SwiftUI sets `allowsUserCustomization` back to
                // false at the *end* of the reconfiguration that emits these adds, so a
                // synchronous re-enable here is immediately clobbered. Re-asserting after
                // the batch settles sticks (verified live: the flag holds once idle).
                DispatchQueue.main.async { self?.enforce() }
            }
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            toolbar = nil
        }

        func enforce() {
            guard let toolbar, !toolbar.allowsUserCustomization else { return }

            // AppKit asserts (crashes) that a *customizable* toolbar must have a unique,
            // non-empty identifier. SwiftUI leaves the merged window toolbar's identifier
            // EMPTY for a section whose content doesn't vend a `.toolbar(id:)` — e.g. the
            // Screen section, whose `NavigationStack` toolbar is uncustomizable — so
            // enabling customization there would crash. Only enable it for an identified
            // toolbar; identified sections (Pads/Questions/…) still get Customize Toolbar…
            // and the observer re-enforces when one of those toolbars is swapped back in.
            guard !toolbar.identifier.isEmpty else { return }

            toolbar.allowsUserCustomization = true
        }
    }
}

/// Suppresses AppKit's tracking separator while the sidebar is collapsed.
/// `NavigationSplitView` adds an `NSTrackingSeparatorToolbarItem` to align a toolbar
/// divider with a split divider. With the sidebar collapsed the content column shifts to
/// the leading edge and narrows, dragging that separator to just after the leading list
/// actions, where it reads as a stray vertical line (#337). There's no SwiftUI API to
/// remove it, and the item's own `view` is `nil` (AppKit draws it internally), so this
/// uses only public `NSToolbar` calls: remove the item while collapsed, re-insert it (the
/// SwiftUI toolbar delegate re-vends it by identifier) when the sidebar reopens.
///
/// The catch is that SwiftUI re-adds the separator whenever it rebuilds the toolbar — e.g.
/// when a selection change swaps in the detail-pane items — so a one-shot removal doesn't
/// hold (confirmed: it reappeared after the launch selection settled). The coordinator
/// therefore also observes `NSToolbar.willAddItemNotification` and re-removes the separator
/// each time it comes back while collapsed. Both directions guard on the item's current
/// presence, so we never create a second copy — a duplicate `splitViewSeparator`
/// identifier is what triggers the `NSToolbar` crash.
struct SidebarSeparatorHider: NSViewRepresentable {
    /// Whether the sidebar is currently collapsed (anything other than `.all`).
    let collapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(from: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    /// Deferred a runloop turn: at make/update time the view may not be in a window yet,
    /// and the toolbar items settle a beat after a visibility change.
    private func apply(from view: NSView, coordinator: Coordinator) {
        let collapsed = collapsed
        DispatchQueue.main.async {
            guard let toolbar = view.window?.toolbar else { return }

            coordinator.collapsed = collapsed
            coordinator.observe(toolbar)
            coordinator.enforce()
        }
    }

    final class Coordinator {
        /// Mirrors the view's `collapsed`, read by `enforce()` (which also runs from the
        /// toolbar notification, outside a SwiftUI update).
        var collapsed = false
        /// The identifier and slot of the separator we removed, so it can be re-inserted
        /// in the same place when the sidebar reopens.
        private var removedIdentifier: NSToolbarItem.Identifier?
        private var removedIndex: Int?
        private weak var toolbar: NSToolbar?
        private var observer: (any NSObjectProtocol)?

        /// Subscribe to the toolbar's item-add notifications so a separator SwiftUI
        /// re-adds while collapsed gets pulled straight back out. Idempotent per toolbar.
        func observe(_ toolbar: NSToolbar) {
            guard self.toolbar !== toolbar else { return }

            stopObserving()
            self.toolbar = toolbar
            observer = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: toolbar,
                queue: .main
            ) { [weak self] _ in
                // The item isn't in `items` yet during the notification, so re-check after.
                DispatchQueue.main.async { self?.enforce() }
            }
        }

        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            toolbar = nil
        }

        /// Removes the tracking separator while collapsed, or restores it once expanded.
        func enforce() {
            guard let toolbar else { return }

            let separatorIndex = toolbar.items.firstIndex { $0 is NSTrackingSeparatorToolbarItem }
            if collapsed {
                if let index = separatorIndex {
                    removedIdentifier = toolbar.items[index].itemIdentifier
                    removedIndex = index
                    toolbar.removeItem(at: index)
                }
            } else if separatorIndex == nil, let identifier = removedIdentifier {
                let index = min(removedIndex ?? toolbar.items.count, toolbar.items.count)
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
                removedIdentifier = nil
                removedIndex = nil
            }
        }
    }
}
