//
//  PadDetailView+Reload.swift
//  coderpad
//

import SwiftUI

extension PadDetailView {
    @ToolbarContentBuilder
    var detailReloadToolbarItem: some CustomizableToolbarContent {
        ToolbarItem(id: "reload-detail", placement: detailToolbarLeadingPlacement) {
            Button {
                Task { await load() }
            } label: {
                Label("Reload Detail", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            .help("Reload events, code, and session playback")
            .accessibilityLabel("Reload pad detail")
        }
    }
}
