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
                    // Read from state rather than scanned here: `installedBrowsers()`
                    // builds a `Bundle` for every candidate app — reading each one's
                    // Info.plist from disk — plus a `FileManager.displayName` call, and
                    // in the body that whole synchronous scan re-ran on every
                    // re-evaluation of the tab (#2447).
                    Picker("Default browser", selection: $defaultBrowserBundleID) {
                        if let systemDefaultBrowserName {
                            Text("Use system default (\(systemDefaultBrowserName))")
                                .tag(String?.none)
                        } else {
                            Text("Use system default")
                                .tag(String?.none)
                        }
                        ForEach(BrowserSettings.pickerBrowsers(
                            installed: installedBrowsers,
                            chosenBundleID: defaultBrowserBundleID
                        )) { browser in
                            Text(browser.name).tag(Optional(browser.bundleID))
                        }
                    }
                }
                Section {
                    Toggle("Open links in background", isOn: $openInBackground)
                } footer: {
                    Text("Some third-party browsers do not support this.")
                        .foregroundStyle(.secondary)
                }
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
            .onAppear {
                // One scan per appearance, reused by the picker above. The cached scan
                // is dropped first so a browser installed or removed since the last
                // visit shows up here (#2160); the open path then reuses this result
                // instead of rescanning per link.
                BrowserSettings.invalidateInstalledBrowsers()
                installedBrowsers = BrowserSettings.installedBrowsers()
                systemDefaultBrowserName = BrowserSettings.systemDefaultBrowserName()
            }
        #endif
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
