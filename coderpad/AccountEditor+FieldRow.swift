//
//  AccountEditor+FieldRow.swift
//  coderpad
//

import SwiftUI

struct AccountEditorLabelWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension AccountEditor {
    var maximumLabelColumnWidth: CGFloat {
        #if os(macOS)
            180
        #else
            144
        #endif
    }

    var labelColumnWidth: CGFloat? {
        measuredLabelColumnWidth > 0 ? min(measuredLabelColumnWidth, maximumLabelColumnWidth) : nil
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
                    .background { intrinsicLabelWidth(label) }
                    .frame(width: labelColumnWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func intrinsicLabelWidth(_ label: String) -> some View {
        Text(LocalizedStringKey(label))
            .fixedSize()
            .hidden()
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: AccountEditorLabelWidthPreference.self, value: geometry.size.width)
                }
            }
    }

    func updateMeasuredLabelWidth(_ width: CGFloat) {
        let rounded = width.rounded(.up)
        if rounded != measuredLabelColumnWidth { measuredLabelColumnWidth = rounded }
    }
}
