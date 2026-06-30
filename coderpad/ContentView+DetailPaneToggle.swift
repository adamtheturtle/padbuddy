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
/// Reads the same `@AppStorage` key the menu command and layout share, so all three
/// stay in lockstep, and animates the swap like the sidebar toggle (#403).
struct DetailPaneToggleToolbarContent: CustomizableToolbarContent {
    @AppStorage(MainSplit.detailPaneHiddenKey) private var detailPaneHidden = false
    /// Snap the pane swap instead of sliding it when Reduce Motion is on (#614).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "toggle-detail-pane", placement: .automatic) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth) { detailPaneHidden.toggle() }
            } label: {
                Label(detailPaneHidden ? "Show Detail Pane" : "Hide Detail Pane",
                      systemImage: "sidebar.right")
            }
            .help(detailPaneHidden ? "Show the detail pane" : "Hide the detail pane")
        }
        .defaultCustomization(.hidden)
    }
}
