//
//  DoubleClickCatcher.swift
//  coderpad
//

import AppKit
import SwiftUI

/// Double-click-to-open for a SwiftUI `List` row, done the native way.
///
/// SwiftUI doesn't expose row double-clicks on macOS, and a SwiftUI `TapGesture`
/// on a row breaks the list's own single-click selection — it either does nothing
/// (#324) or makes selection laggy and unfocused/grey (#326). A per-row
/// `NSViewRepresentable` with a click recognizer never even receives the clicks,
/// because the list's row hosting doesn't route mouse events to it.
///
/// The underlying `NSTableView` already supports a `doubleAction` that fires
/// alongside — and never interferes with — its native single-click selection. So
/// we set that. Because the first click of a double-click selects the row, the
/// action just opens the *current selection*, with no need to map a click location
/// back to a row.
///
/// `NSTableView.target` is `weak`, so the target can't be a row view (rows are
/// reused and deallocated as you scroll, which would silently drop the action).
/// The list owns a ``TableDoubleClickProxy`` in `@State`; an installer attached to
/// a row finds the enclosing table and points its `doubleAction` at that long-lived
/// proxy.
@MainActor
final class TableDoubleClickProxy: NSObject {
    /// Opens the row the user double-clicked. Set by the list; reads its live
    /// selection, so it stays correct as the selection changes.
    var onDoubleClick: () -> Void = {}
    /// The table whose `doubleAction` we own, kept to ignore double-clicks that land
    /// below the last row (`clickedRow == -1`) so empty space never opens anything.
    weak var tableView: NSTableView?
    /// The table's original target (SwiftUI's own coordinator). A table shares one
    /// `target` between its single-click `action` and its `doubleAction`, so taking
    /// over `target` to receive double-clicks also redirects the single-click
    /// `action` (`onAction:`) here. We forward any selector we don't implement back
    /// to this original target so SwiftUI's click handling keeps working instead of
    /// crashing on an unrecognized selector.
    ///
    /// `nonisolated(unsafe)` because the forwarding override below must match
    /// `NSObject`'s nonisolated signature; both are only ever touched on the main
    /// thread, where AppKit dispatches table target/action messages.
    nonisolated(unsafe) weak var forwardingTarget: NSObject?

    @objc func fire() {
        guard let tableView, tableView.clickedRow >= 0 else { return }
        onDoubleClick()
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if let forwardingTarget, forwardingTarget.responds(to: selector) {
            return forwardingTarget
        }
        return super.forwardingTarget(for: selector)
    }
}

/// Points the enclosing `NSTableView`'s `doubleAction` at `proxy`. Attached to a
/// row (via `.background`) so the table is reachable by walking up the view tree;
/// re-asserts on update in case the list rebuilds the table.
struct TableDoubleClickInstaller: NSViewRepresentable {
    let proxy: TableDoubleClickProxy

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view isn't in the table's hierarchy yet at make time, so defer.
        DispatchQueue.main.async { install(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { install(from: nsView) }
    }

    private func install(from view: NSView) {
        guard let table = view.enclosingTableView else { return }
        proxy.tableView = table
        // Preserve SwiftUI's existing target so the table's single-click `action`
        // (`onAction:`) still reaches it after we take over `target` for `doubleAction`.
        if let existing = table.target as? NSObject, existing !== proxy {
            proxy.forwardingTarget = existing
        }
        table.target = proxy
        table.doubleAction = #selector(TableDoubleClickProxy.fire)
    }
}

private extension NSView {
    /// The nearest `NSTableView` ancestor, or `nil` if this view isn't inside one.
    var enclosingTableView: NSTableView? {
        var candidate = superview
        while let view = candidate {
            if let table = view as? NSTableView { return table }
            candidate = view.superview
        }
        return nil
    }
}

extension View {
    /// Installs the list double-click handler from this row. Pair with a single
    /// ``TableDoubleClickProxy`` owned by the list, whose `onDoubleClick` opens the
    /// current selection. See ``TableDoubleClickProxy`` for why the proxy lives on
    /// the list rather than the row.
    func installsTableDoubleClick(_ proxy: TableDoubleClickProxy) -> some View {
        background(TableDoubleClickInstaller(proxy: proxy))
    }
}
