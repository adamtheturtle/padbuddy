//
//  SettingsView+BrowserMenuBar.swift
//  coderpad
//
//  The Browser and Menu Bar settings tabs, split from SettingsView+Tabs.swift to keep
//  that file within the lint length limit. Both tabs are only reachable on macOS (see
//  SettingsView's tab list), though browserTab compiles cross-platform.
//

import SwiftUI

extension SettingsView {
    var browserTab: some View {
        Form {
            // Choosing a specific external browser app and opening it in the background
            // are macOS-only; on iPad external links always go to the system default.
            #if os(macOS)
                Section {
                    Picker("Default browser", selection: $defaultBrowserBundleID) {
                        Text("Use system default (\(BrowserSettings.systemDefaultBrowserName()))")
                            .tag(String?.none)
                        ForEach(BrowserSettings.installedBrowsers()) { browser in
                            Text(browser.name).tag(Optional(browser.bundleID))
                        }
                    }
                }
                Section {
                    Toggle("Open links in background", isOn: $openInBackground)
                } footer: {
                    Text("Some third-party browsers don't support this.")
                        .foregroundStyle(.secondary)
                }
            #endif
        }
        .formStyle(.grouped)
    }

    var menuBarTab: some View {
        Form {
            // The tab is always present (#608) so the Settings layout stays stable; when
            // the menu-bar icon is turned off (Dock-only mode) the controls below have no
            // effect, so explain that and disable them rather than making the whole tab
            // vanish and reappear.
            if !presence.showsMenuBarIcon {
                Section {
                    Text("The menu-bar icon is turned off. Turn it on under General, "
                        + "“Show PadBuddy in”, to use these settings.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Stepper(value: $menuBarTopN, in: 0 ... 30, step: 1) {
                    HStack {
                        Text("Recent pads in menu bar")
                        Spacer()
                        Text("\(menuBarTopN)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Show only active pads", isOn: $menuBarStartedOnly)
            }
        }
        .formStyle(.grouped)
        .disabled(!presence.showsMenuBarIcon)
    }
}
