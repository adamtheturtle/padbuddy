//
//  DesignSystem.swift
//  coderpad
//

import SwiftUI

// The generic, domain-free design-system primitives — colour tokens, `Spacing`,
// `ChipContrast`, `Card`, `DetailSection`, `SectionHeader`, `LabeledRow`, `StatTile`,
// `Chip`, `MetaLabel`, `AvatarCircle`, `ReloadToolbarButton` — now live in the
// `BuddyDesignSystem` product of the shared `buddy-kit` package (#377, #516) so they
// can be shared with the HackerRank app. Re-exported here so the rest of the app keeps
// using them unqualified, with no per-file import. The app-coupled helpers built on
// top of them stay below.
@_exported import BuddyDesignSystem

// The NSTableView-backed list (`FastList`, `SwipeAction`, `MenuItem`) was lifted out
// of `BuddyDesignSystem` into the standalone `FastList` package (#548). Re-exported here
// so the four list columns keep using it unqualified, the same way the rest of the
// design system is shared.
@_exported import FastList

/// A pad's lifecycle state. A live pad is the one status that genuinely benefits
/// from standing out, so it keeps a subtle green capsule; every other state reads
/// as restrained secondary metadata (an SF Symbol + text, see ``MetaLabel``) so the
/// list doesn't fill up with competing coloured pills.
struct StateBadge: View {
    let state: PadState
    /// Under "Increase Contrast" the subtle tinted fill/stroke are strengthened so
    /// the badge stays legible for low-vision users (see ChipContrast).
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if state == .active {
            Text(state.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(ChipContrast.fill(0.16, contrast)), in: Capsule())
                .foregroundStyle(.green)
                .overlay(Capsule().stroke(Color.green.opacity(ChipContrast.stroke(0.25, contrast)),
                                          lineWidth: ChipContrast.lineWidth(contrast)))
        } else {
            MetaLabel(text: state.label, systemImage: state.systemImage)
        }
    }
}

extension AvatarCircle {
    /// Builds the avatar from an account: its chosen symbol and tint when set,
    /// otherwise the name's initials on the account's default tint.
    init(account: Account, diameter: CGFloat = 32) {
        self.init(label: account.name, diameter: diameter,
                  tint: account.avatarTint, symbol: account.iconSymbol)
    }
}
