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
/// Setting the underlying `NSTableView`'s `doubleAction` looked like the answer, but
/// SwiftUI's table subclass doesn't route through that AppKit action, so it never
/// fired (#330). Instead we add our own `NSClickGestureRecognizer` (two clicks
/// required) directly to the table view: a recognizer on the table receives clicks
/// on any row, and with `delaysPrimaryMouseButtonEvents = false` it observes them
/// without delaying delivery — so the list's native single-click selection stays
/// instant (blue and immediate), and only a genuine double-click fires our action.
/// Because the first click of the pair already selected the row, the action just
/// opens the *current selection*, with no need to map a click location back to a row.
///
/// The recognizer's target is `weak` (as a gesture recognizer's target always is),
/// so it can't be a row view (rows are reused and deallocated as you scroll, which
/// would silently drop the action). The list owns a ``TableDoubleClickProxy`` in
/// `@State`; an installer attached to a row finds the enclosing table and installs
/// the recognizer there, targeting that long-lived proxy.
@MainActor
final class TableDoubleClickProxy: NSObject {
    /// Opens the row the user double-clicked. Set by the list; reads its live
    /// selection, so it stays correct as the selection changes.
    var onDoubleClick: () -> Void = {}
    /// The table we've already installed the recognizer on, so each of the list's
    /// rows asking to install doesn't add a duplicate recognizer.
    weak var installedTable: NSTableView?

    @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let table = recognizer.view as? NSTableView else { return }
        // Ignore double-clicks in the empty space below the last row so blank
        // space never opens anything.
        let point = recognizer.location(in: table)
        guard table.row(at: point) >= 0 else { return }
        onDoubleClick()
    }
}

/// Installs the list's double-click recognizer on the enclosing `NSTableView`.
/// Attached to a row (via `.background`) so the table is reachable by walking up the
/// view tree; re-asserts on update in case the list rebuilds the table.
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
        // Every row runs this; only the first installs the recognizer per table.
        guard proxy.installedTable !== table else { return }
        let recognizer = NSClickGestureRecognizer(
            target: proxy,
            action: #selector(TableDoubleClickProxy.handleDoubleClick(_:))
        )
        recognizer.numberOfClicksRequired = 2
        // Observe clicks without delaying their delivery to the table, so the
        // list's single-click selection stays instant; only the second click of a
        // double fires our action.
        recognizer.delaysPrimaryMouseButtonEvents = false
        table.addGestureRecognizer(recognizer)
        proxy.installedTable = table
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
