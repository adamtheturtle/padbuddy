//
//  SettingsView+Notifications.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    func handleNotificationPreference(_ enabled: Bool) {
        guard enabled else {
            PreferenceCloudSync.shared.notificationPreferenceChanged(
                key: GeneralSettings.Key.notifyOnPadUpdates
            )
            return
        }

        Task {
            let available = await PadUpdateNotifier.shared.alertAuthorizationIsAvailable()
            guard notifyOnPadUpdates else { return }

            notificationPermissionDenied = !available
            if !available { notifyOnPadUpdates = false }
        }
    }

    func sendTestNotification() {
        notificationTestMessage = "Sending…"
        Task {
            let accountName = store.accounts.first { $0.id == notificationPreviewAccountID }?.name
            let sent = await PadUpdateNotifier.shared.postTestNotification(accountName: accountName)
            notificationPermissionDenied = !sent
            notificationTestMessage = sent
                ? String(localized: "Test sent. Check Notification Center if no banner appeared.")
                : String(localized: "Test could not be sent. Check notification permission in System Settings.")
        }
    }
}
