//
//  coderpadApp.swift
//  coderpad
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct coderpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("CoderPad", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        WindowGroup("Pad Browser", id: "pad-browser", for: URL.self) { $url in
            if let url {
                PadBrowserView(url: url)
                    .navigationTitle(url.host ?? "Pad")
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("CoderPad", systemImage: "doc.text.magnifyingglass") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
