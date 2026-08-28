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

        notificationAttempt &+= 1
        let attempt = notificationAttempt
        Task {
            let available = await PadUpdateNotifier.shared.alertAuthorizationIsAvailable()
            // Checking only that the preference is currently on was not enough: a quick
            // off-then-on left the first request in flight, and its failure then turned
            // off the newer enable the user had just made (#4608).
            guard notificationAttempt == attempt, notifyOnPadUpdates else { return }

            notificationPermissionDenied = !available
            if !available {
                notifyOnPadUpdates = false
            }
        }
    }

    func sendTestNotification() {
        guard !isSendingTestNotification else { return }

        notificationAttempt &+= 1
        let attempt = notificationAttempt
        isSendingTestNotification = true
        notificationTestMessage = String(localized: "Sending…")
        Task {
            let accountName = store.accounts.first { $0.id == notificationPreviewAccountID }?.name
            let sent = await PadUpdateNotifier.shared.postTestNotification(accountName: accountName)
            // Cleared unconditionally: only one test runs at a time, and leaving this set
            // would disable the button for good if the preference flow bumped the attempt
            // counter while this was in flight.
            isSendingTestNotification = false
            // A slower earlier request must not publish over a newer one's result (#4607).
            guard notificationAttempt == attempt else { return }

            notificationPermissionDenied = !sent
            notificationTestMessage = sent
                ? String(localized: "Test sent. Check Notification Center if no banner appeared.")
                : String(localized: "Test could not be sent. Check notification permission in System Settings.")
        }
    }
}
