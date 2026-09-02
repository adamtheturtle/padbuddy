//
//  SettingsView+Whiteboard.swift
//  coderpad
//

import SwiftUI

extension SettingsView {
    var whiteboardCacheSettingsSection: some View {
        Section {
            Button(role: .destructive) {
                WhiteboardImageCache.shared.clear()
            } label: {
                Label("Clear Whiteboard Image Cache", systemImage: "photo.stack")
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Removes downloaded whiteboard thumbnails. They will be downloaded again when needed.")
                .foregroundStyle(.secondary)
        }
    }
}
