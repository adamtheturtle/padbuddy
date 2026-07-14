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
                if scope != .off { PadUpdateNotifier.shared.requestBadgeAuthorization() }
                DockBadgeController.refresh()
            }
            #if os(macOS)
            .disabled(!presence.showsDockIcon)
            #endif
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
