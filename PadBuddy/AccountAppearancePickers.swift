//
//  AccountAppearancePickers.swift
//  coderpad
//

import SwiftUI

/// A compact row of curated SF Symbols for an account's avatar.
struct AccountSymbolPicker: View {
    @Binding var selection: String?
    private let columns = [GridItem(.adaptive(minimum: 28), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            symbolButton(nil, glyph: "textformat", help: "Use initials")
            ForEach(Account.iconSymbolChoices, id: \.self) { symbol in
                symbolButton(symbol, glyph: symbol, help: Account.iconSymbolName(symbol))
            }
        }
    }

    private func symbolButton(_ value: String?, glyph: String, help: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.chip))
                .overlay(RoundedRectangle(cornerRadius: Radius.chip)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A compact row of curated tint swatches for an account's avatar.
struct AccountTintPicker: View {
    @Binding var selection: String?
    let defaultColor: Color
    private let columns = [GridItem(.adaptive(minimum: 24), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            swatch(nil, color: defaultColor, help: "Default color")
            ForEach(Account.tintChoices, id: \.self) { hex in
                swatch(hex, color: Color(hex: hex) ?? .gray, help: Account.tintName(hex))
            }
        }
    }

    private func swatch(_ value: String?, color: Color, help: String) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.9 : 0.15),
                                         lineWidth: isSelected ? 2 : 0.5))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
