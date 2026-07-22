//
//  SettingsAccess.swift
//  coderpad
//
//  A cross-platform "open the app's settings" action. macOS has a dedicated `Settings`
//  scene reached through the system `\.openSettings` environment action; iPadOS has no
//  such scene, so there the action raises an in-app sheet instead. Views call a single
//  `\.openAppSettings` action and stay platform-agnostic; the per-platform wiring lives in
//  one place (`provideAppSettingsAction()` and its scene-local presentation).
//

import SwiftUI

/// A callable "open settings" action injected through the environment. Using
/// `callAsFunction` lets call sites keep writing `openSettings()` unchanged.
struct OpenAppSettingsAction {
    let perform: @MainActor () -> Void

    @MainActor func callAsFunction() {
        perform()
    }
}

extension EnvironmentValues {
    /// The cross-platform settings action. Defaults to a no-op until a scene provides the
    /// real one via ``SwiftUI/View/provideAppSettingsAction()``.
    @Entry var openAppSettings: OpenAppSettingsAction = .init(perform: {})
}

extension View {
    /// Injects the cross-platform `\.openAppSettings` action for descendants. Apply this once
    /// per scene, above the content that opens settings. On macOS it forwards to the system
    /// `Settings` scene; on visionOS and iPadOS it raises an in-app settings presentation.
    func provideAppSettingsAction() -> some View {
        modifier(AppSettingsActionProvider())
    }
}

private struct AppSettingsActionProvider: ViewModifier {
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings

        func body(content: Content) -> some View {
            content.environment(\.openAppSettings, OpenAppSettingsAction { openSettings() })
        }
    #else
        /// Scene-local presentation (#838): each window owns its own flag, so opening
        /// Settings covers only the initiating window - a process-wide singleton would
        /// present (and dismiss) the cover in every open iPad window at once.
        @State private var isPresented = false

        func body(content: Content) -> some View {
            #if os(visionOS)
                content
                    .environment(\.openAppSettings, OpenAppSettingsAction { isPresented = true })
                    // A scene-local sheet is reliable from the first-run window on
                    // visionOS; opening a second Settings window from that empty state
                    // could silently fail (#2920).
                    .sheet(isPresented: $isPresented) {
                        NavigationStack {
                            SettingsView()
                                .frame(width: 720, height: 620)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { isPresented = false }
                                            .buttonStyle(.bordered)
                                    }
                                }
                        }
                        .presentationSizing(.fitted)
                        .presentationBackground(.thickMaterial)
                        .presentationCornerRadius(28)
                    }
            #else
                content
                    .environment(\.openAppSettings, OpenAppSettingsAction { isPresented = true })
                    // A full-screen cover, not a `.sheet`: on iPad a sheet is a centered form
                    // sheet whose faint scrim let the parent's empty-state text and window
                    // chrome bleed around the card edges and read as broken (#577/#578). A
                    // full cover hides the background entirely; the Done button dismisses it.
                    .fullScreenCover(isPresented: $isPresented) {
                        NavigationStack {
                            SettingsView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { isPresented = false }
                                    }
                                }
                        }
                    }
            #endif
        }
    #endif
}
