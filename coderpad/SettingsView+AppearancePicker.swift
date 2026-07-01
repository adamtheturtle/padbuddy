//
//  SettingsView+AppearancePicker.swift
//  coderpad
//
//  Split out of SettingsView+Models.swift to keep each file under the length limit.
//

import SwiftUI

/// A visual appearance picker mirroring macOS System Settings: a row of preview
/// tiles the user clicks, rather than a plain menu. Each tile renders a swatch in
/// its own appearance — System split light/dark — with a selection ring and a
/// labelled radio beneath it.
struct AppearancePicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(AppAppearance.allCases) { option in
                tile(option)
            }
        }
    }

    private func tile(_ option: AppAppearance) -> some View {
        let isSelected = selection == option
        // The whole tile — swatch *and* the radio/label beneath it — is one button,
        // so clicking the circle under the picture selects the option too (#493).
        return Button {
            selection = option
        } label: {
            VStack(spacing: 6) {
                AppearanceSwatch(appearance: option)
                    .frame(width: 104, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.subtleStroke,
                                    lineWidth: isSelected ? 3 : 1)
                    )
                Label {
                    Text(option.label).font(.callout)
                } icon: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .font(.callout)
            }
            // Keep the whole tile area hit-testable, including the gap between
            // the swatch and the label.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection = option }
    }
}

/// The preview swatch inside an ``AppearancePicker`` tile: a small mock desktop and
/// window rendered in the given appearance, so the choice is recognizable at a
/// glance. System shows a diagonal light/dark split.
private struct AppearanceSwatch: View {
    let appearance: AppAppearance

    var body: some View {
        ZStack {
            background
            // A small mock window to read as a desktop rather than a flat colour.
            RoundedRectangle(cornerRadius: Radius.tight, style: .continuous)
                .fill(windowFill)
                .overlay(RoundedRectangle(cornerRadius: Radius.tight, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 60, height: 36)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 4, height: 4)
                        }
                    }
                    .padding(6)
                }
        }
    }

    @ViewBuilder private var background: some View {
        switch appearance {
        case .light: Color(white: 0.90)
        case .dark: Color(white: 0.16)
        case .system:
            LinearGradient(
                stops: [.init(color: Color(white: 0.90), location: 0.5),
                        .init(color: Color(white: 0.16), location: 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var windowFill: Color {
        switch appearance {
        case .light: .white
        case .dark: Color(white: 0.30)
        case .system: Color(white: 0.55)
        }
    }
}
