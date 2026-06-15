//
//  DoubleClickCatcher.swift
//  coderpad
//

import AppKit
import SwiftUI

/// Adds double-click handling to a `List` row without disturbing the list's own
/// single-click selection.
///
/// A SwiftUI `TapGesture` attached to a macOS `List` row swallows the native
/// click-to-select: by default a click recognizer delays primary mouse-button
/// events until recognition fails, so a plain click either does nothing (#324)
/// or — when selection is then driven manually — lags a double-click interval and
/// shows the unfocused grey highlight instead of the focused blue one (#326).
///
/// Instead, install an `NSClickGestureRecognizer` with
/// `delaysPrimaryMouseButtonEvents = false`. The recognizer still observes every
/// click (it sees events before any view does), but it no longer delays or
/// consumes them, so each click flows straight through to the list for its native,
/// instant, focused selection. Only a genuine double-click also fires `action`.
///
/// The recognizer is added to a transparent overlay sized to the row. Every
/// modifier the row relies on — the list's selection, the row's `.contextMenu`,
/// and `.draggable` — is an ancestor of this overlay, so the events it forwards up
/// the responder chain still reach them.
struct DoubleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick)
        )
        recognizer.numberOfClicksRequired = 2
        // Let the click (and the first click of a double) reach the list, so its
        // own selection still fires — immediately and focused (blue), not grey.
        recognizer.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the fired closure current as rows are reused for different items.
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handleDoubleClick() { action() }
    }
}

extension View {
    /// Opens on double-click while leaving the list's single-click selection
    /// untouched. See ``DoubleClickCatcher`` for why this isn't a SwiftUI gesture.
    func onRowDoubleClick(perform action: @escaping () -> Void) -> some View {
        overlay(DoubleClickCatcher(action: action))
    }
}
