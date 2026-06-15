//
//  DoubleClickCatcher.swift
//  coderpad
//

import AppKit
import SwiftUI

/// Adds double-click handling to a `List` row without slowing — or breaking — the
/// list's own single-click selection.
///
/// A SwiftUI `TapGesture` on a macOS `List` row swallows the native
/// click-to-select: a click recognizer delays primary mouse-button events until
/// recognition fails, so a plain click either does nothing (#324) or, once
/// selection is driven manually, lags and shows the unfocused grey highlight
/// instead of the focused blue one (#326).
///
/// An overlay that merely sets `delaysPrimaryMouseButtonEvents = false` selects
/// correctly but is still the click's hit-test target, so the event reaches the
/// list only after being forwarded — a small but real delay to the blue highlight.
///
/// So this view is transparent to hit-testing (`hitTest` returns `nil`): every
/// click lands directly on the row beneath it and the list selects natively —
/// instantly, with the focused blue highlight, and with ⌘/⇧-click multi-select
/// intact. The double-click recognizer is installed on the row's container rather
/// than on this view, so it still observes double-clicks without ever being their
/// target.
struct DoubleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughClickView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Keep the fired closure current as rows are reused for different items;
        // the recognizer's target is this same coordinator, so it always opens the
        // row currently shown.
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func handleDoubleClick() { action() }
    }

    /// Lays out over the row but never intercepts a click; it installs the
    /// double-click recognizer on its superview (the row's container) so the
    /// recognizer still sees clicks on the row while the row itself stays the
    /// hit-test target for the list's instant native selection.
    final class PassthroughClickView: NSView {
        weak var coordinator: Coordinator?
        private weak var recognizerHost: NSView?
        private weak var installedRecognizer: NSClickGestureRecognizer?

        // The click belongs to the list row underneath, not to us.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            installRecognizer()
        }

        /// Attaches a double-click recognizer to the current superview, moving it if
        /// the row's container changed (list row reuse). A no-op while it's already
        /// installed on the same host, so it never stacks duplicates.
        private func installRecognizer() {
            guard let coordinator else { return }
            let host = superview
            if recognizerHost === host { return }
            if let installedRecognizer, let recognizerHost {
                recognizerHost.removeGestureRecognizer(installedRecognizer)
            }
            installedRecognizer = nil
            recognizerHost = nil
            guard let host else { return }
            let recognizer = NSClickGestureRecognizer(
                target: coordinator, action: #selector(Coordinator.handleDoubleClick)
            )
            recognizer.numberOfClicksRequired = 2
            // Don't delay the click reaching the list, so selection stays instant.
            recognizer.delaysPrimaryMouseButtonEvents = false
            host.addGestureRecognizer(recognizer)
            installedRecognizer = recognizer
            recognizerHost = host
        }
    }
}

extension View {
    /// Opens on double-click while leaving the list's single-click selection fully
    /// native — instant and focused. See ``DoubleClickCatcher`` for why this isn't a
    /// SwiftUI gesture.
    func onRowDoubleClick(perform action: @escaping () -> Void) -> some View {
        overlay(DoubleClickCatcher(action: action))
    }
}
