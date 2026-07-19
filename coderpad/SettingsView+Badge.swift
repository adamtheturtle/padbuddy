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

extension SettingsView {
    /// Lets the user forget which pads they've looked at.
    ///
    /// The app records a pad identifier and a timestamp each time you open a pad,
    /// so a started pad can show an activity dot when it changes *since you last
    /// looked*. Those records are held on this device and mirrored to iCloud.
    /// They age out after 90 days, but waiting was previously the only way to be
    /// rid of them (#2629).
    var padHistorySection: some View {
        Section {
            Button("Clear Pad View History", role: .destructive) {
                showClearPadHistoryConfirmation = true
            }
            .confirmationDialog("Clear pad view history?",
                                isPresented: $showClearPadHistoryConfirmation,
                                titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    PadOpenedStore.shared.clearAllHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                Every started pad will show as changed until you open it again. \
                This clears the history on all your devices.
                """)
            }
        } footer: {
            Text("""
            PadBuddy remembers when you last opened each pad so it can flag ones that \
            changed since. Records are kept for 90 days.
            """)
            .foregroundStyle(.secondary)
        }
    }
}
