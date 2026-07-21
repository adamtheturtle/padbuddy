//
//  SettingsView+Whiteboard.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    var whiteboardCacheSettingsSection: some View {
        Section {
            Button("Clear Whiteboard Image Cache", role: .destructive) {
                WhiteboardImageCache.shared.clear()
            }
        } footer: {
            Text("Removes downloaded whiteboard thumbnails. They will be downloaded again when needed.")
                .foregroundStyle(.secondary)
        }
    }
}
