//
//  PadDetailView+Toolbar.swift
//  coderpad
//
//  Where the detail pane's toolbar items sit on each platform. Split from
//  PadDetailView.swift to keep that file under the file-length limit.
//

import SwiftUI

extension PadDetailView {
    var detailToolbarLeadingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarLeading
        #endif
    }

    var detailToolbarTrailingPlacement: ToolbarItemPlacement {
        #if os(macOS)
            .primaryAction
        #else
            .topBarTrailing
        #endif
    }
}
