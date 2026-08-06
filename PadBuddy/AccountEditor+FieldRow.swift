//
//  AccountEditor+FieldRow.swift
//  coderpad
//

import SwiftUI

extension AccountEditor {
    var maximumLabelColumnWidth: CGFloat {
        #if os(macOS)
            180
        #else
            144
        #endif
    }

    var labelColumnWidth: CGFloat {
        maximumLabelColumnWidth
    }

    var usesCompactAccountEditorLayout: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }

    @ViewBuilder
    func fieldRow(_ label: String,
                  alignment: VerticalAlignment = .firstTextBaseline,
                  @ViewBuilder content: () -> some View) -> some View {
        if usesCompactAccountEditorLayout {
            VStack(alignment: .leading, spacing: 4) {
                if !label.isEmpty {
                    Text(LocalizedStringKey(label))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: alignment, spacing: 10) {
                Text(LocalizedStringKey(label))
                    .multilineTextAlignment(.trailing)
                    .frame(width: labelColumnWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
