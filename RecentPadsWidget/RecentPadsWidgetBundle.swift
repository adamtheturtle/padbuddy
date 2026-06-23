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
/// On Mac, controls surface in Control Center and as menu bar items. Tapping it runs
/// `CreatePadIntent`, which records the request in the App Group and opens the app to
/// the create flow. It can't use `OpenURLIntent`: that only opens universal (https)
/// links, never the app's `coderpad://` custom scheme, so the control did nothing
/// (#485).
@available(macOS 26.0, *)
struct NewPadControl: ControlWidget {
    static let kind = "com.adamdangoor.padbuddy.NewPadControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: CreatePadIntent()) {
                Label("New Pad", systemImage: "plus.square.on.square")
            }
        }
        .displayName("New Pad")
        .description("Create a new CoderPad pad.")
    }
}
