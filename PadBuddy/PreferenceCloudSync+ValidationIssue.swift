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
        // Nothing in Settings corresponds to these, so an alert sending the user
        // there had no remedy behind it. They are list-toolbar and filter-bar state
        // that the next interaction rewrites anyway, so an invalid snapshot is
        // discarded quietly — the refusal is already logged by the caller (#4807).
        guard !Self.silentlyDiscardedKeys.contains(key) else { return }
        guard !validationIssues.contains(where: { $0.key == key }) else { return }

        validationIssues.append(ValidationIssue(
            key: key,
            settingName: Self.settingNames[key] ?? key,
            destination: Self.settingsDestination(for: key)
        ))
    }

    func clearValidationIssue(for key: String) {
        validationIssues.removeAll { $0.key == key }
    }

    /// Dismisses the issue currently on screen, leaving any others to be presented in
    /// turn rather than discarding them unseen.
    func dismissValidationIssue() {
        guard !validationIssues.isEmpty else { return }

        validationIssues.removeFirst()
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

    /// The synced keys with no Settings control to send the user to: the two sort
    /// orders belong to the list toolbar, and the merged live filters are the filter
    /// bar's own state.
    static let silentlyDiscardedKeys: Set<String> = [
        "pads.sort",
        "questions.sort",
        "pads.merged.liveFilter",
        "questions.merged.liveFilter"
    ]

    private static let settingNames = [
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
