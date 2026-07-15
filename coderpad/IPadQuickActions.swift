//
//  IPadQuickActions.swift
//  coderpad
//
//  Home Screen quick actions for iPadOS. These mirror the macOS Dock menu actions
//  and route through AppNavigation so cold-launch and already-running selections use
//  the same durable navigation state as deep links, commands, and widgets.
//

#if !os(macOS)
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
        private var pendingShortcutItem: UIApplicationShortcutItem?

        func scene(
            _: UIScene,
            willConnectTo _: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions
        ) {
            pendingShortcutItem = connectionOptions.shortcutItem
        }

        func sceneDidBecomeActive(_: UIScene) {
            guard let pendingShortcutItem else { return }

            self.pendingShortcutItem = nil
            _ = IPadQuickAction.handle(pendingShortcutItem)
        }

        func windowScene(
            _: UIWindowScene,
            performActionFor shortcutItem: UIApplicationShortcutItem,
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(IPadQuickAction.handle(shortcutItem))
        }
    }

    private enum IPadQuickAction: String {
        case newPad = "com.adamdangoor.padbuddy.new-pad"
        case newQuestion = "com.adamdangoor.padbuddy.new-question"
        case showPads = "com.adamdangoor.padbuddy.show-pads"
        case showQuestions = "com.adamdangoor.padbuddy.show-questions"

        @MainActor
        static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
            guard let action = Self(rawValue: shortcutItem.type) else { return false }

            action.perform()
            return true
        }

        @MainActor
        private func perform() {
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
#endif
