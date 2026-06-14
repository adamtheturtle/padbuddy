//
//  PadUpdateNotifier.swift
//  coderpad
//
//  Posts macOS Notification Center alerts when pads you can see gain new activity,
//  reusing the same change detection that already drives the Dock badge and the
//  menu-bar "updated" count (`PadActivityMonitor`). Opt-in: nothing is posted unless
//  the user enables it in Settings *and* grants notification permission, and alerts
//  are suppressed while the app is frontmost (you're already looking) so it stays
//  quiet. Tapping an alert deep-links back into the app via the existing
//  `coderpad://` routing.
//

import AppKit
import UserNotifications

@MainActor
final class PadUpdateNotifier: NSObject {
    static let shared = PadUpdateNotifier()

    private let center = UNUserNotificationCenter.current()

    /// A single, stable identifier so repeated bursts of activity coalesce into one
    /// alert ("3 pads updated" replaces "2 pads updated") rather than stacking up a
    /// pile of banners — the same "never noisy" intent as the self-clearing badge.
    private static let notificationID = "coderpad.padUpdates"

    private override init() { super.init() }

    /// Wire this object up as the notification-center delegate so taps route into the
    /// app. Call once at launch (from `AppDelegate`).
    func register() {
        center.delegate = self
    }

    /// Ask the system for permission to post alerts. Called when the user opts in, so
    /// the permission prompt appears at a moment they expect it rather than at launch.
    func requestAuthorization() {
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    /// Post an alert summarizing pads that just gained activity. A no-op unless the
    /// user opted in, and skipped while the app is active so it only fires for
    /// background activity. Authorization is requested lazily the first time so a user
    /// who flipped the toggle before granting permission is still prompted.
    func notify(changedPads: [Pad]) {
        guard GeneralSettings.notifyOnPadUpdates,
              !changedPads.isEmpty,
              !NSApp.isActive else { return }
        Task { await post(changedPads: changedPads) }
    }

    private func post(changedPads: [Pad]) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        case .denied:
            return
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        if changedPads.count == 1, let pad = changedPads.first {
            content.title = "Pad updated"
            content.body = pad.title.isEmpty ? "Untitled pad" : pad.title
            // Deep-link straight to the one pad that changed.
            content.userInfo = ["url": "coderpad://pad/\(pad.id)"]
        } else {
            content.title = "Pads updated"
            content.body = "\(changedPads.count) pads have new activity"
            // No single pad to single out, so just bring the Pads list forward.
            content.userInfo = ["url": "coderpad://pads"]
        }

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

extension PadUpdateNotifier: UNUserNotificationCenterDelegate {
    /// Show the banner even if the app happens to be frontmost when it's delivered —
    /// `notify` already gates on `isActive`, so this only matters for an alert that
    /// lands just as the app regains focus.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Route a tapped alert through the app's own `coderpad://` deep links, which both
    /// open the target and surface a main window when none is up — the same path the
    /// widget and Dock menu use.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
