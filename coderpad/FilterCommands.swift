//
//  FilterCommands.swift
//  coderpad
//

import SwiftUI

struct FilterCommands: Commands {
    @FocusedValue(\.clearFiltersAction) private var clearFiltersAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Clear All Filters") { clearFiltersAction?.perform() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(clearFiltersAction == nil)
        }
    }
}
