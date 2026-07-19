//
//  ContentView+DetailPaneToggle.swift
//  coderpad
//

import SwiftUI

/// An opt-in toolbar button that hides or shows the detail (third) pane (#404).
/// Hidden by default in the customizable toolbar — the View ▸ Hide Detail Pane
/// menu item (⌃⌘D, #394) is the primary control — but available to drag in via
/// Customize Toolbar for users who flip to the thin two-column layout often. Lives
/// in the always-present list-column toolbars (Pads/Questions, single and merged),
/// not the detail toolbar, so "Show" is still reachable once the pane is hidden.
/// Drives the same focused action the menu command uses, so the button, the menu
/// item, and the layout stay in lockstep within a window — and all three disable
/// together in a section with no detail column (#2301, #2302). Animates the swap like
/// the sidebar toggle (#403).
struct DetailPaneToggleToolbarContent: CustomizableToolbarContent {
    @FocusedValue(\.detailPaneToggleAction) private var toggle
    /// Snap the pane swap instead of sliding it when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "toggle-detail-pane", placement: .automatic) {
            let hidden = toggle?.hidden == true
            Button {
                withAnimation(reduceMotion ? nil : .smooth) { toggle?.perform() }
            } label: {
                Label(hidden ? "Show Detail Pane" : "Hide Detail Pane",
                      systemImage: "sidebar.right")
            }
            .help(hidden ? "Show the detail pane" : "Hide the detail pane")
            .disabled(toggle == nil)
        }
        .defaultCustomization(.hidden)
    }
}
