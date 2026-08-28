//
//  PadUpdateNotifier+Delegate.swift
//  coderpad
//
//  Routing a tapped pad-update alert back into the app.
//

#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif
import Foundation
import os
import UserNotifications

extension PadUpdateNotifier: UNUserNotificationCenterDelegate {
    nonisolated static func presentationOptions(appIsActive: Bool) -> UNNotificationPresentationOptions {
        appIsActive ? [] : [.banner, .sound]
    }

    /// Delivery can lag scheduling; re-check the current application state so a
    /// notification queued in the background stays quiet after foregrounding.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == Self.testNotificationID {
            return [.banner, .sound]
        }
        let active = await appIsActive
        return Self.presentationOptions(appIsActive: active)
    }

    /// Route a tapped alert through the app's own `com.adamdangoor.padbuddy://` deep links, which both
    /// open the target and surface a main window when none is up — the same path the
    /// widget and Dock menu use.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run { AppActivator.bringToFront() }
        if let urlString, let url = URL(string: urlString) {
            await URLOpener.open(url)
        }
    }
}
