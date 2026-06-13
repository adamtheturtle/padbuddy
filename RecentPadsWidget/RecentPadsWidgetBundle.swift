//
//  RecentPadsWidgetBundle.swift
//  RecentPadsWidget
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct RecentPadsWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentPadsWidget()
        // Controls reached the Mac (Control Center / menu bar) in macOS 26; the
        // extension still deploys to macOS 15 for the widget itself, so gate the
        // control on availability and leave the widget unconditional.
        if #available(macOS 26.0, *) {
            NewPadControl()
        }
    }
}

/// A control that creates a new pad straight from Control Center or the menu bar.
/// On Mac, controls surface in Control Center and as menu bar items. Tapping it
/// opens the app to the new-pad flow via the `coderpad://new-pad` deep link the app
/// already routes — a system `OpenURLIntent` performs the open, so no app-only
/// intent has to be compiled into this dependency-free widget extension.
@available(macOS 26.0, *)
struct NewPadControl: ControlWidget {
    static let kind = "ptn.coderpad.NewPadControl"

    /// The deep link the app handles by switching to Pads and opening the create
    /// sheet. Force-unwrapped: a malformed literal would fail every build.
    private static let newPadURL = URL(string: "coderpad://new-pad")!

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(Self.newPadURL)) {
                Label("New Pad", systemImage: "plus.square.on.square")
            }
        }
        .displayName("New Pad")
        .description("Create a new CoderPad pad.")
    }
}
