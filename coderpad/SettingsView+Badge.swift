//
//  SettingsView+Badge.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    var badgeSettingsSection: some View {
        Section {
            Picker(badgeSettingTitle, selection: $dockBadgeScope) {
                ForEach(DockBadgeScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .onChange(of: dockBadgeScope) { _, scope in
                updateBadgeScope(scope)
            }
            #if os(macOS)
            .disabled(!presence.showsDockIcon)
            #endif
        }
    }

    private func updateBadgeScope(_ scope: DockBadgeScope) {
        guard scope != .off else {
            DockBadgeController.refresh()
            return
        }

        Task { @MainActor in
            let isAvailable = await PadUpdateNotifier.shared.badgeAuthorizationIsAvailable()
            if !isAvailable, dockBadgeScope == scope {
                dockBadgeScope = .off
            }
            DockBadgeController.refresh()
        }
    }

    private var badgeSettingTitle: LocalizedStringKey {
        #if os(macOS)
            "Show my active pads on the Dock icon"
        #else
            "Show my active pads on the app icon"
        #endif
    }
}

