//
//  SettingsView+AccountsUI.swift
//  coderpad
//

import SwiftUI

/// The Mail-style segmented add/remove control shown at the foot of the accounts
/// sidebar: a single rounded pill with a `+` and `−` separated by a hairline divider,
/// mirroring the table-footer control used throughout macOS System Settings and Mail.
struct AddRemoveControl: View {
    let onAdd: () -> Void
    let onRemove: () -> Void
    let canRemove: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("plus", help: "Add account", label: "Add account", action: onAdd)
            Divider()
                .frame(height: 14)
            segment("minus", help: "Remove selected account",
                    label: "Remove selected account", action: onRemove)
                .disabled(!canRemove)
        }
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.subtleStroke, lineWidth: 1)
        )
        .fixedSize()
    }

    private func segment(_ symbol: String,
                         help: String,
                         label: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }
}

struct AccountRow: View {
    let account: Account
    let isCurrent: Bool
    @State private var monitor = AccountHealthMonitor.shared

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(account: account, diameter: 30)

            HStack(spacing: 6) {
                Text(account.name.isEmpty ? String(localized: "Untitled account") : account.name)
                    .font(.callout.weight(.medium))
                if account.isMock {
                    Text("Demo")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.purple.opacity(0.18), in: Capsule())
                        .foregroundStyle(.purple)
                }
                if account.isBadKeyDemo || monitor.isUnauthorized(account.id) {
                    Text("Bad key")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                }
                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
