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
        .background(Color.platformControlBackground,
                    in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
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

    /// The account's name bounded for a one-line row (#1629): control characters
    /// stripped and the length capped, so a pathological name can't make account
    /// selection/removal rows ambiguous or blow up VoiceOver labels.
    private var displayName: String {
        let cleaned = String(account.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return String(localized: "Untitled account") }

        return String(cleaned.prefix(80))
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(account: account, diameter: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(statusText, systemImage: statusSymbol)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    if account.hasScreenAccess {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                            .help("CoderPad Screen connected")
                            .accessibilityLabel("CoderPad Screen connected")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var hasInvalidKey: Bool {
        account.isBadKeyDemo || monitor.isUnauthorized(account.id)
    }

    private var statusText: String {
        if hasInvalidKey {
            return String(localized: "API key needs attention")
        }
        if isCurrent {
            return String(localized: "Current account")
        }
        if account.isMock {
            return String(localized: "Demo account")
        }
        if let baseURL = account.baseURL,
           let host = URL(string: baseURL)?.host,
           !host.isEmpty {
            return host
        }
        return String(localized: "CoderPad account")
    }

    private var statusSymbol: String {
        if hasInvalidKey {
            return "exclamationmark.triangle.fill"
        }
        if isCurrent {
            return "checkmark.circle.fill"
        }
        if account.isMock {
            return "sparkles"
        }
        return "globe"
    }

    private var statusColor: Color {
        if hasInvalidKey {
            return .red
        }
        if isCurrent {
            return .green
        }
        if account.isMock {
            return .purple
        }
        return .secondary
    }

    private var accessibilityLabel: String {
        var parts = [displayName, statusText]
        if account.hasScreenAccess {
            parts.append(String(localized: "CoderPad Screen connected"))
        }
        return parts.joined(separator: ", ")
    }
}
