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

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import Foundation
import os
import UserNotifications

/// A single pad's change since the last sweep, classified into the most
/// meaningful thing that happened so the notification can describe it rather
/// than just saying "updated". Produced by the pad list's diff (`padChanges`).
struct PadChange {
    /// The kinds of activity we can tell apart from two consecutive snapshots,
    /// ordered loosely by how noteworthy they are. `updated` is the catch-all
    /// for a bump we can't attribute to anything more specific.
    enum Kind {
        case new
        case ended
        case participantJoined
        case updated

        /// The phrase shown as the notification body for a single changed pad.
        var detail: String {
            switch self {
            case .new: String(localized: "New pad")
            case .ended: String(localized: "Interview ended")
            case .participantJoined: String(localized: "Someone joined")
            case .updated: String(localized: "New activity")
            }
        }
    }

    let pad: Pad
    let kind: Kind
}

@MainActor
final class PadUpdateNotifier: NSObject {
    static let shared = PadUpdateNotifier()

    private let center = UNUserNotificationCenter.current()
    /// Per-identifier coalescing state: repeated bursts for one account replace
    /// that account's own alert, while different accounts' alerts stand side by
    /// side instead of cancelling each other (#1144, refining #1038).
    private var notificationGenerations: [String: Int] = [:]
    private var notificationTasks: [String: Task<Void, Never>] = [:]

    /// The stable identifier prefix; the owning account's id is appended so each
    /// organization coalesces onto its own alert (#1144).
    private static let notificationID = "coderpad.padUpdates"
    private static let padPathAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Diagnostics for notifications that fail to schedule.
    private static let notificationLogger = Logger(subsystem: "com.coderpad.app", category: "pad-notifications")

    override private init() {
        super.init()
    }

    /// Wire this object up as the notification-center delegate so taps route into the
    /// app. Call once at launch (from `AppDelegate`).
    func register() {
        center.delegate = self
    }

    /// Returns whether the app can currently post pad-update alerts, requesting alert
    /// permission first (the system prompts at most once and otherwise returns the
    /// standing decision). Callers that expose the notify preference use this to avoid
    /// leaving an enabled-looking setting in place when every alert would be
    /// dropped (#836).
    func alertAuthorizationIsAvailable() async -> Bool {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        } catch {
            return false
        }

        let settings = await center.notificationSettings()
        return settings.authorizationStatus != .denied
    }

    /// Re-asserts badge permission at launch without ever presenting a first-time
    /// prompt. Since macOS Monterey, `NSDockTile.badgeLabel` only renders for an app
    /// granted the `.badge` capability; iOS app-icon badges use the same authorization
    /// option (#317/#679). A persisted badge scope is not a fresh user action, so an
    /// undetermined status waits for the user to touch the badge setting (which
    /// requests via `badgeAuthorizationIsAvailable()`) rather than prompting out of
    /// context at launch (#1961); an already-determined status just returns the
    /// standing decision with no UI.
    func refreshBadgeAuthorizationIfDetermined() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus != .notDetermined else { return }

            _ = await badgeAuthorizationIsAvailable()
        }
    }

    /// Returns whether the app can currently render an icon badge after requesting
    /// badge permission. Callers that expose a badge preference use this to avoid
    /// leaving an enabled-looking setting in place when the system will drop updates.
    func badgeAuthorizationIsAvailable() async -> Bool {
        do {
            guard try await center.requestAuthorization(options: [.badge]) else { return false }
        } catch {
            return false
        }

        let settings = await center.notificationSettings()
        return settings.authorizationStatus != .denied && settings.badgeSetting == .enabled
    }

    /// Post an alert summarizing pads that just gained activity in `account`. A
    /// no-op unless the user opted in, and skipped while the app is active so it
    /// only fires for background activity. Authorization is never requested here:
    /// the Settings toggle's own flow prompts (#836), so a background refresh
    /// can't surface the system permission dialog at an arbitrary moment (#1143).
    func notify(changes: [PadChange], account: Account? = nil) {
        guard GeneralSettings.notifyOnPadUpdates,
              !changes.isEmpty,
              !appIsActive else { return }

        let identifier = account.map { "\(Self.notificationID).\($0.id.uuidString)" } ?? Self.notificationID
        let generation = (notificationGenerations[identifier] ?? 0) + 1
        notificationGenerations[identifier] = generation
        notificationTasks[identifier]?.cancel()
        notificationTasks[identifier] = Task {
            await post(changes: changes, accountName: account?.name, accountID: account?.id,
                       identifier: identifier, generation: generation)
        }
    }

    /// Cancels scheduling and removes every pending or delivered pad-update alert.
    /// Enumerating Notification Center also catches identifiers created by a previous
    /// launch, while the prefix guard leaves unrelated app notifications untouched.
    func removeAllPadUpdateNotifications() {
        notificationTasks.values.forEach { $0.cancel() }
        notificationTasks.removeAll()
        notificationGenerations.removeAll()

        Task {
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            center.removePendingNotificationRequests(withIdentifiers: pending
                .map(\.identifier)
                .filter(Self.isPadUpdateNotificationIdentifier))
            center.removeDeliveredNotifications(withIdentifiers: delivered
                .map(\.request.identifier)
                .filter(Self.isPadUpdateNotificationIdentifier))
        }
    }

    static func isPadUpdateNotificationIdentifier(_ identifier: String) -> Bool {
        identifier == notificationID || identifier.hasPrefix("\(notificationID).")
    }

    /// Whether the app is frontmost, used to suppress alerts you'd already see. Spelled
    /// per platform: `NSApp.isActive` on macOS, the foreground-active scene phase on iOS.
    private var appIsActive: Bool {
        #if os(macOS)
            NSApp.isActive
        #else
            UIApplication.shared.applicationState == .active
        #endif
    }

    private func post(changes: [PadChange], accountName: String?, accountID: UUID?,
                      identifier: String, generation: Int) async {
        let settings = await center.notificationSettings()
        // Re-check activity after every await too: the app can come to the front
        // while settings are being read, and an alert (let alone a permission
        // prompt) must not fire for a foregrounded refresh (#1143).
        // The preference is re-checked after the await, not only before: reading
        // settings suspends, and a banner must not appear for a toggle the user turned
        // off while it was in flight (#2175).
        guard isCurrent(identifier: identifier, generation: generation),
              GeneralSettings.notifyOnPadUpdates,
              !appIsActive else { return }

        switch settings.authorizationStatus {
        case .notDetermined, .denied:
            // Undetermined just means no alert yet: the permission prompt belongs
            // to the Settings toggle's flow, never to a background refresh (#1143).
            return

        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        let hideTitles = GeneralSettings.hidePadTitlesInNotifications
        // Name the organization so a multi-account user can tell whose pads have
        // activity (#1144); single-account setups skip the redundant subtitle.
        if let accountName, !accountName.isEmpty, AccountsStore.shared.accounts.count > 1 {
            content.subtitle = accountName
        }
        if changes.count == 1, let change = changes.first {
            // Lead with the pad's own name so the alert names what changed, and
            // put the kind of activity in the body. With titles hidden, the alert
            // still says something happened and where to look, but names nothing
            // that could identify a candidate on a lock screen (#2178).
            if hideTitles {
                content.title = String(localized: "Pad updated")
            } else {
                content.title = change.pad.title.isEmpty ? "Untitled pad" : change.pad.title
            }
            content.body = change.kind.detail
            // Deep-link straight to the one pad that changed.
            // The owning account travels with the id: pad slugs are only unique per
            // server, so a bare id could open a same-slug pad in whichever account
            // happened to be current when the alert was tapped (#2173).
            if let link = Self.notificationURL(padID: change.pad.id, accountID: accountID) {
                content.userInfo = ["url": link.absoluteString]
            }
        } else {
            content.title = "Pads updated"
            content.body = hideTitles
                ? String(localized: "^[\(changes.count) pads](inflect: true) have new activity.")
                : Self.summary(of: changes)
            // No single pad to single out, so just bring the Pads list forward.
            let listURL = Self.padsNotificationURL(accountID: accountID)?.absoluteString ?? "coderpad://pads"
            content.userInfo = ["url": listURL]
        }

        guard isCurrent(identifier: identifier, generation: generation),
              GeneralSettings.notifyOnPadUpdates,
              !appIsActive else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            // Silently swallowing this left an opted-in feature quietly not working
            // with nothing to diagnose it from (#2177). The pad titles stay out of the
            // log; only the failure reason is recorded.
            Self.notificationLogger.error("""
            Failed to schedule a pad update notification: \(error.localizedDescription, privacy: .private)
            """)
        }
    }

    private func isCurrent(identifier: String, generation: Int) -> Bool {
        !Task.isCancelled && generation == notificationGenerations[identifier]
    }

    static func notificationURL(padID: String, accountID: UUID?) -> URL? {
        guard !padID.isEmpty,
              let encodedID = padID.addingPercentEncoding(withAllowedCharacters: padPathAllowed) else { return nil }

        var components = URLComponents()
        components.scheme = "coderpad"
        components.host = "pad"
        components.percentEncodedPath = "/\(encodedID)"
        if let accountID {
            components.queryItems = [URLQueryItem(name: "account", value: accountID.uuidString)]
        }
        return components.url
    }

    static func padsNotificationURL(accountID: UUID?) -> URL? {
        var components = URLComponents()
        components.scheme = "coderpad"
        components.host = "pads"
        if let accountID {
            components.queryItems = [URLQueryItem(name: "account", value: accountID.uuidString)]
        }
        return components.url
    }

    /// A one-line body for a burst of changes. When they're all the same kind we
    /// can be specific ("3 new pads"); a mix falls back to a plain count so the
    /// line stays short and readable.
    static func summary(of changes: [PadChange]) -> String {
        let count = changes.count
        let kinds = Set(changes.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else {
            return String(localized: "\(count) pads have new activity")
        }

        switch kind {
        case .new: return String(localized: "\(count) new pads")
        case .ended: return String(localized: "\(count) interviews ended")
        case .participantJoined: return String(localized: "\(count) pads gained a participant")
        case .updated: return String(localized: "\(count) pads have new activity")
        }
    }
}

extension PadUpdateNotifier: UNUserNotificationCenterDelegate {
    nonisolated static func presentationOptions(appIsActive: Bool) -> UNNotificationPresentationOptions {
        appIsActive ? [] : [.banner, .sound]
    }

    /// Delivery can lag scheduling; re-check the current application state so a
    /// notification queued in the background stays quiet after foregrounding.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let active = await appIsActive
        return Self.presentationOptions(appIsActive: active)
    }

    /// Route a tapped alert through the app's own `coderpad://` deep links, which both
    /// open the target and surface a main window when none is up — the same path the
    /// widget and Dock menu use.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let urlString = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run {
            AppActivator.bringToFront()
            if let urlString, let url = URL(string: urlString) {
                URLOpener.open(url)
            }
        }
    }
}
