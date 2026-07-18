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

    /// Ask the system for permission to put a count on the app icon. Since macOS
    /// Monterey, `NSDockTile.badgeLabel` only renders for an app granted the `.badge`
    /// capability; iOS app-icon badges use the same authorization option (#317/#679).
    /// Requesting it is idempotent: the system prompts at most once and otherwise just
    /// returns the standing decision, so it's safe to call on every launch and whenever
    /// the badge scope is switched on.
    func requestBadgeAuthorization() {
        Task { _ = await badgeAuthorizationIsAvailable() }
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
            await post(changes: changes, accountName: account?.name,
                       identifier: identifier, generation: generation)
        }
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

    private func post(changes: [PadChange], accountName: String?, identifier: String, generation: Int) async {
        let settings = await center.notificationSettings()
        // Re-check activity after every await too: the app can come to the front
        // while settings are being read, and an alert (let alone a permission
        // prompt) must not fire for a foregrounded refresh (#1143).
        guard isCurrent(identifier: identifier, generation: generation), !appIsActive else { return }

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
        // Name the organization so a multi-account user can tell whose pads have
        // activity (#1144); single-account setups skip the redundant subtitle.
        if let accountName, !accountName.isEmpty, AccountsStore.shared.accounts.count > 1 {
            content.subtitle = accountName
        }
        if changes.count == 1, let change = changes.first {
            // Lead with the pad's own name so the alert names what changed, and
            // put the kind of activity in the body.
            content.title = change.pad.title.isEmpty ? "Untitled pad" : change.pad.title
            content.body = change.kind.detail
            // Deep-link straight to the one pad that changed.
            content.userInfo = ["url": "coderpad://pad/\(change.pad.id)"]
        } else {
            content.title = "Pads updated"
            content.body = Self.summary(of: changes)
            // No single pad to single out, so just bring the Pads list forward.
            content.userInfo = ["url": "coderpad://pads"]
        }

        guard isCurrent(identifier: identifier, generation: generation), !appIsActive else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func isCurrent(identifier: String, generation: Int) -> Bool {
        !Task.isCancelled && generation == notificationGenerations[identifier]
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
    /// Show the banner even if the app happens to be frontmost when it's delivered —
    /// `notify` already gates on `isActive`, so this only matters for an alert that
    /// lands just as the app regains focus.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
