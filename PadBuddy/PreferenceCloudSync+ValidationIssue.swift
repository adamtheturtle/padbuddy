//
//  PreferenceCloudSync+ValidationIssue.swift
//  coderpad
//

import Foundation

extension PreferenceCloudSync {
    struct ValidationIssue: Identifiable {
        let key: String
        let settingName: String
        let destination: SettingsTab
        var id: String {
            key
        }
    }

    func reportValidationIssue(for key: String) {
        validationIssue = ValidationIssue(
            key: key,
            settingName: Self.settingNames[key] ?? key,
            destination: Self.settingsDestination(for: key)
        )
    }

    func clearValidationIssue(for key: String) {
        if validationIssue?.key == key {
            validationIssue = nil
        }
    }

    func dismissValidationIssue() {
        validationIssue = nil
    }

    private static func settingsDestination(for key: String) -> SettingsTab {
        if key.hasPrefix("browser.") {
            return .browser
        }
        if key == "general.presence" {
            return .menuBar
        }
        return .general
    }

    private static let settingNames = [
        "pads.sort": String(localized: "Pad sort order"),
        "questions.sort": String(localized: "Question sort order"),
        "pads.merged.liveFilter": String(localized: "All-accounts pad filters"),
        "questions.merged.liveFilter": String(localized: "All-accounts question filters"),
        "general.appearance": String(localized: "Appearance"),
        "general.dockBadgeScope": String(localized: "Dock badge"),
        "general.spotlightIndexing": String(localized: "Spotlight indexing"),
        "general.notifyOnPadUpdates": String(localized: "Pad update notifications"),
        "general.hidePadTitlesInNotifications": String(localized: "Notification privacy"),
        "general.presence": String(localized: "Dock and menu bar presence"),
        "browser.defaultBrowserBundleID": String(localized: "Default browser"),
        "browser.openInBackground": String(localized: "Open browser in background")
    ]
}
