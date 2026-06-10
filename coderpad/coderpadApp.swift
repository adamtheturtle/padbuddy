//
//  coderpadApp.swift
//  coderpad
//

import SwiftUI

@main
struct coderpadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}
