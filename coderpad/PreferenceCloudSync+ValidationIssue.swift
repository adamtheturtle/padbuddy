//
//  PreferenceCloudSync+ValidationIssue.swift
//  coderpad
//

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
        if validationIssue?.key == key { validationIssue = nil }
    }

    func dismissValidationIssue() {
        validationIssue = nil
    }

    private static func settingsDestination(for key: String) -> SettingsTab {
        if key.hasPrefix("browser.") { return .browser }
        if key == "general.presence" { return .menuBar }
        return .general
    }

    private static let settingNames = [
        "pads.sort": "Pad sort order",
        "questions.sort": "Question sort order",
        "pads.merged.liveFilter": "All-accounts pad filters",
        "questions.merged.liveFilter": "All-accounts question filters",
        "general.appearance": "Appearance",
        "general.dockBadgeScope": "Dock badge",
        "general.spotlightIndexing": "Spotlight indexing",
        "general.notifyOnPadUpdates": "Pad update notifications",
        "general.hidePadTitlesInNotifications": "Notification privacy",
        "general.presence": String(localized: "Dock and menu bar presence"),
        "browser.defaultBrowserBundleID": String(localized: "Default browser"),
        "browser.openInBackground": String(localized: "Open browser in background")
    ]
}
