//
//  SettingsAccess.swift
//  coderpad
//
//  A cross-platform "open the app's settings" action. macOS has a dedicated `Settings`
//  scene reached through the system `\.openSettings` environment action; iPadOS has no
//  such scene, so there the action raises an in-app sheet instead. Views call a single
//  `\.openAppSettings` action and stay platform-agnostic; the per-platform wiring lives in
//  one place (`provideAppSettingsAction()` + the iPad sheet in the scene).
//

import SwiftUI

/// A callable "open settings" action injected through the environment. Using
/// `callAsFunction` lets call sites keep writing `openSettings()` unchanged.
struct OpenAppSettingsAction {
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() { perform() }
}

private struct OpenAppSettingsKey: EnvironmentKey {
    static let defaultValue = OpenAppSettingsAction(perform: {})
}

extension EnvironmentValues {
    /// The cross-platform settings action. Defaults to a no-op until a scene provides the
    /// real one via ``SwiftUI/View/provideAppSettingsAction()``.
    var openAppSettings: OpenAppSettingsAction {
        get { self[OpenAppSettingsKey.self] }
        set { self[OpenAppSettingsKey.self] = newValue }
    }
}

#if !os(macOS)
    /// iPad settings-sheet presentation state (no macOS-style `Settings` scene on iOS). The
    /// main window observes this to present `SettingsView` as a sheet.
    @MainActor @Observable final class SettingsPresentation {
        static let shared = SettingsPresentation()
        private init() {}

        var isPresented = false
    }
#endif

extension View {
    /// Injects the cross-platform `\.openAppSettings` action for descendants. Apply this once
    /// per scene, above the content that opens settings. On macOS it forwards to the system
    /// `Settings` scene; on iPad it raises the in-app settings sheet.
    func provideAppSettingsAction() -> some View {
        modifier(AppSettingsActionProvider())
    }
}

private struct AppSettingsActionProvider: ViewModifier {
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
            content.environment(\.openAppSettings, OpenAppSettingsAction { openSettings() })
        #else
            content.environment(\.openAppSettings, OpenAppSettingsAction {
                SettingsPresentation.shared.isPresented = true
            })
        #endif
    }
}
