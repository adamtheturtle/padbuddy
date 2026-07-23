//
//  IPadQuickActions.swift
//  coderpad
//
//  Home Screen quick actions for iPadOS. These mirror the macOS Dock menu actions
//  and route through AppNavigation so cold-launch and already-running selections use
//  the same durable navigation state as deep links, commands, and widgets.
//

#if os(iOS)
    import UIKit

    final class IPadQuickActionAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            configurationForConnecting connectingSceneSession: UISceneSession,
            options _: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
            if connectingSceneSession.role == .windowApplication {
                configuration.delegateClass = IPadQuickActionSceneDelegate.self
            }
            return configuration
        }
    }

    final class IPadQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
        private var queue = IPadQuickActionQueue()

        func scene(
            _: UIScene,
            willConnectTo _: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions
        ) {
            guard let shortcutItem = connectionOptions.shortcutItem else { return }

            _ = queue.enqueue(type: shortcutItem.type)
        }

        func sceneDidBecomeActive(_: UIScene) {
            queue.activate()
            perform(queue.drain())
        }

        func windowScene(
            _: UIWindowScene,
            performActionFor shortcutItem: UIApplicationShortcutItem,
            completionHandler: (Bool) -> Void
        ) {
            // A shortcut can arrive before the scene is active, so queue it rather than
            // running it against navigation state that is not ready yet (#2032).
            let recognised = queue.enqueue(type: shortcutItem.type)
            perform(queue.drain())
            completionHandler(recognised)
        }

        @MainActor
        private func perform(_ actions: [IPadQuickAction]) {
            for action in actions {
                action.perform()
            }
        }
    }
#endif

/// Buffers quick actions that arrive before the scene becomes active.
///
/// Only one shortcut used to be remembered, so a second one delivered before activation
/// silently replaced the first; actions are now kept in arrival order (#2032).
struct IPadQuickActionQueue {
    private var pending: [IPadQuickAction] = []
    private var isActive = false

    /// Records `type`, returning whether it names a known quick action.
    mutating func enqueue(type: String) -> Bool {
        guard let action = IPadQuickAction(rawValue: type) else { return false }

        pending.append(action)
        return true
    }

    /// Marks the scene as active so queued actions can run.
    mutating func activate() {
        isActive = true
    }

    /// The actions to perform now, in arrival order. Empty until the scene is active.
    mutating func drain() -> [IPadQuickAction] {
        guard isActive else { return [] }

        defer { pending.removeAll() }
        return pending
    }
}

/// The Home Screen quick actions, kept platform-neutral so the macOS build type-checks them.
enum IPadQuickAction: String {
    case newPad = "com.adamdangoor.padbuddy.new-pad"
    case newQuestion = "com.adamdangoor.padbuddy.new-question"
    case showPads = "com.adamdangoor.padbuddy.show-pads"
    case showQuestions = "com.adamdangoor.padbuddy.show-questions"

    /// List shortcuts remain useful without an account; creation shortcuts must
    /// not enter an unsatisfiable flow on cold launch or while offline.
    func isAvailable(canCreate: Bool) -> Bool {
        switch self {
        case .newPad, .newQuestion: canCreate
        case .showPads, .showQuestions: true
        }
    }

    @MainActor
    func perform() {
        let canCreate = AppCreationAvailability.canCreate(
            accounts: AccountsStore.shared,
            network: NetworkMonitor.shared
        )
        guard isAvailable(canCreate: canCreate) else { return }

        switch self {
        case .newPad:
            AppNavigation.shared.showPads(PadsRequest(startCreating: true))
        case .newQuestion:
            AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
        case .showPads:
            AppNavigation.shared.show(.pads)
        case .showQuestions:
            AppNavigation.shared.show(.questions)
        }
    }
}
