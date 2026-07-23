//
//  PadRow+Support.swift
//  coderpad
//
//  Split from PadRow.swift to keep it within the lint length limit: the row
//  support types shared by the pad and question rows moved here.
//

import SwiftUI

#if DEBUG
    /// Per-selection render profiler (#439). Counts how many memoized row-content bodies
    /// (`PadRowInfo` / `QuestionRowInfo`) evaluate per selection change, plus the rough
    /// main-thread stall. With the `NSTableView`-backed `FastList` the table doesn't
    /// re-host rows on a selection change, so this should stay near zero — what's left of
    /// the stall is the detail-pane/selection cascade, not the list. Wired up from a
    /// list's selection `onChange`; DEBUG-only so it never ships in release.
    @MainActor
    enum SelectionProfiler {
        static var memoizedEvals = 0

        static func memoizedTick() {
            memoizedEvals += 1
        }

        /// Call from the list's selection `onChange`. Resets the counter, then reads it
        /// back after the current update cycle drains to approximate the stall.
        static func selectionChanged() {
            let start = CFAbsoluteTimeGetCurrent()
            memoizedEvals = 0
            DispatchQueue.main.async {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print(String(format: "⏱️ #439 selection stall ≈ %.1fms — memoized row bodies = %d",
                             elapsedMs, memoizedEvals))
            }
        }
    }
#endif

/// The account a merged-list row belongs to, reduced to just what the row renders:
/// the name plus the avatar's tint and symbol. `nil` in the per-account lists, where
/// every row shares one account and naming it on each row would be noise.
/// `Equatable`/`Hashable` (a plain value type) so the memoized row body re-renders
/// when the account's identity changes, and so it can sit inside the `Hashable`
/// merged-row models. (#604)
struct RowAccount: Equatable, Hashable {
    let name: String
    let tint: Color
    let symbol: String?

    init(_ account: Account) {
        name = account.name
        tint = account.avatarTint
        symbol = account.iconSymbol
    }
}

struct FavoriteRowHoverIdentity: Equatable {
    let itemID: String
    let account: RowAccount?
}

/// Names the account a merged-list row came from, using the account's own avatar
/// (its tint + chosen symbol, or its initials) rather than a generic person glyph —
/// so multi-account users can tell at a glance which account a pad/question belongs
/// to, matching the avatar shown in the org/quota headers and the sidebar footer.
/// Styled like ``MetaLabel`` so it sits cleanly among the row's other metadata. (#604)
struct AccountMetaLabel: View {
    let account: RowAccount

    var body: some View {
        HStack(spacing: 4) {
            AvatarCircle(label: account.name, diameter: 14, tint: account.tint, symbol: account.symbol)
            // Unlike the short, `.fixedSize` chips beside it, an account name is
            // free-form and can be long, so let it truncate with a tail ellipsis
            // ("Fawlty Tow…") rather than staying whole and being hard-clipped
            // mid-glyph by `clipsMetadataOverflow` on a narrow list column.
            Text(account.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color.fastListRowSecondaryLabel.opacity(0.88))
    }
}

struct AccountTintRail: View {
    let account: RowAccount
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Capsule(style: .continuous)
            .fill(account.tint.opacity(contrast == .increased ? 0.95 : 0.75))
            .frame(width: 4, height: 36)
            .overlay {
                if contrast == .increased {
                    Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

extension Color {
    static var fastListRowPrimaryLabel: Color {
        #if os(iOS)
            Color(platformColor: .label)
        #else
            .primary
        #endif
    }

    static var fastListRowSecondaryLabel: Color {
        #if os(iOS)
            Color(platformColor: .secondaryLabel)
        #else
            .secondary
        #endif
    }
}
