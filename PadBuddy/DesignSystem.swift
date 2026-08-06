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

// The print / Save-as-PDF core (`printDocument`, `PrintSection`, `PrintCode`) now
// lives in the standalone `PrintableView` package (#652). Re-exported here so the
// existing print document call sites keep using those symbols unqualified.
#if os(macOS) || os(iOS)
    @_exported import PrintableView
#endif

// The NSTableView-backed list (`FastList`, `SwipeAction`, `MenuItem`) was lifted out
// of `BuddyDesignSystem` into the standalone `FastList` package (#548). It is *not*
// re-exported here: each list surface imports FastList explicitly, so the app's
// real coupling to the package stays visible per file while its API surface is
// narrowed (#683, FastList#4).

extension Spacing {
    /// Vertical rhythm between fields in compact detail groups.
    static let contentGroupGap: CGFloat = 10
    /// Vertical rhythm for sheet-level form stacks.
    static let sheetGap: CGFloat = 14
    /// Horizontal inset for compact inline controls such as chips and address pills.
    static let compactControlH: CGFloat = 10
    /// Vertical inset for compact inline controls such as chips.
    static let compactControlV: CGFloat = 5
    /// Interior padding for compact popovers and empty states.
    static let popoverInset: CGFloat = 10
}

extension AppSection {
    var label: String {
        switch self {
        case .pads: String(localized: "Pads")
        case .questions: String(localized: "Questions")
        case .organization: String(localized: "Organization")
        case .quota: String(localized: "Quota")
        case .screen: String(localized: "Screen")
        }
    }

    var shortLabel: String {
        switch self {
        case .organization: String(localized: "Org")
        default: label
        }
    }

    var systemImage: String {
        switch self {
        case .pads: "doc.text"
        case .questions: "questionmark.bubble"
        case .organization: "building.2"
        case .quota: "gauge.with.dots.needle.67percent"
        case .screen: "person.crop.rectangle.stack"
        }
    }
}

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
            activeBadge
        } else {
            MetaLabel(text: state.label, systemImage: state.systemImage)
        }
    }

    private var activeBadge: some View {
        Text(state.label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(ChipContrast.fill(0.22, contrast)), in: Capsule())
            .foregroundStyle(Color.green)
            .overlay(Capsule().stroke(Color.green.opacity(ChipContrast.stroke(0.42, contrast)),
                                      lineWidth: ChipContrast.lineWidth(contrast)))
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
