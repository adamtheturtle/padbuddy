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
                Task { await load(visibleRefreshControls: true) }
            } label: {
                Label("Reload Detail", systemImage: "arrow.clockwise")
            }
            .tint(.accentColor)
            .disabled(showsRefreshControls)
            .help("Reload events, code, and session playback")
            .accessibilityLabel("Reload pad detail")
        }
    }
}
