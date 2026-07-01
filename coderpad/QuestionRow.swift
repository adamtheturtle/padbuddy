//
//  QuestionRow.swift
//  coderpad
//

import SwiftUI

/// The question row's static title/metadata/date block — the bulk of the row's
/// render cost — memoized via `.equatable()` by ``QuestionRowHostableContent`` (#439). It holds no
/// interaction and no closures, so wrapping it in an `EquatableView` can't affect the
/// row's hit-testing or selection. `==` compares only the fields it renders.
private struct QuestionRowInfo: View, Equatable {
    let question: Question
    let account: RowAccount?

    static func == (lhs: Self, rhs: Self) -> Bool {
        let lhsq = lhs.question, rhsq = rhs.question
        return lhsq.id == rhsq.id
            && lhsq.title == rhsq.title
            && lhsq.language == rhsq.language
            && lhsq.interviewType == rhsq.interviewType
            && lhsq.used == rhsq.used
            && lhsq.isDraft == rhsq.isDraft
            && lhsq.authorName == rhsq.authorName
            && lhsq.updatedAt == rhsq.updatedAt
            && lhs.account == rhs.account
    }

    var body: some View {
        #if DEBUG
            // `let _` is required inside a ViewBuilder (a bare `_ =` isn't a valid
            // builder expression), so silence redundant_discardable_let here.
            // swiftlint:disable:next redundant_discardable_let
            let _ = SelectionProfiler.memoizedTick()
        #endif
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let account {
                        AccountMetaLabel(account: account)
                    }
                    if let lang = question.language, !lang.isEmpty {
                        MetaLabel(text: lang.languageDisplayName)
                    }
                    if question.interviewType == .takeHome {
                        InterviewType.takeHome.chip
                    }
                    if let used = question.used, used > 0 {
                        MetaLabel(text: String(localized: "Used \(used)×"), systemImage: "chart.bar")
                    }
                    if question.isDraft == true {
                        Chip(text: String(localized: "Draft"), systemImage: "doc.badge.ellipsis", tint: .orange)
                    }
                }
                .lineLimit(1)
                if let author = question.authorName {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        // Read the title + metadata block as one VoiceOver element with a
        // coherent label (mirroring PadRow), rather than stopping on each chip
        // and label separately; the favorite star stays its own action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The row's title and metadata composed into one VoiceOver phrase, matching
    /// PadRow so the two lists read consistently. The favorite toggle keeps its own
    /// label, so it isn't folded in here.
    private var accessibilityLabel: String {
        var parts = [question.displayTitle]
        if let account { parts.append(account.name) }
        if let lang = question.language, !lang.isEmpty {
            parts.append(lang.languageDisplayName)
        }
        if question.interviewType == .takeHome { parts.append("Take-home") }
        if let used = question.used, used > 0 { parts.append("used \(used) times") }
        if question.isDraft == true { parts.append("Draft") }
        if let author = question.authorName { parts.append(author) }
        if let lastUsed = question.updatedAt {
            parts.append("last used \(RelativeDateLabel.labels(for: lastUsed).relative)")
        }
        return parts.joined(separator: ", ")
    }
}

/// The question row's right-aligned "last used" date column, mirroring
/// ``PadRowDateLabel`` so the favorite star lands in the same slot on both lists —
/// info, then star, then a fixed date column — rather than the star sitting to the
/// right of the date on questions but to its left on pads (#650). Reserves the shared
/// column width even when a question has never been used so the star stays aligned.
private struct QuestionRowDateLabel: View {
    let lastUsed: Date?

    var body: some View {
        Group {
            if let lastUsed {
                // Cached labels rather than `.formatted` per render — see PadRow (#439).
                let labels = RelativeDateLabel.labels(for: lastUsed)
                Text(labels.relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Last used \(labels.tooltip)")
                    .frame(minWidth: FastListRowMetrics.dateColumnWidth, alignment: .trailing)
            } else {
                // Reserve exactly the column width so unused questions keep the
                // star/date column aligned with used ones (mirrors PadRowDateLabel, #635).
                Color.clear
                    .frame(width: FastListRowMetrics.dateColumnWidth)
            }
        }
        .layoutPriority(1)
        .allowsHitTesting(false)
    }
}

/// The question row as hosted inside the `NSTableView`-backed `FastList` (#439). The
/// title/metadata block is `.allowsHitTesting(false)` so left-clicks pass through the
/// `NSHostingView` to the table for native selection; only the favorite star stays
/// hittable. Mirrors ``PadRowHostableContent``. Selection, double-click, swipe, drag,
/// and the context menu are the table's job.
struct QuestionRowHostableContent: View {
    let question: Question
    /// The account this row belongs to, named on the row only in the merged list
    /// (`nil` in the per-account list). (#604)
    var rowAccount: RowAccount?
    /// Resolved by the list owner so the hosted row doesn't read the `@Observable`
    /// favorites store while `NSTableView` recycles cells during scroll (#633).
    var isFavorite: Bool
    /// Toggles the favorite via the owning view's method (which may also clear the
    /// Favorites filter when the last star is removed), rather than the store directly.
    var onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            QuestionRowInfo(question: question, account: rowAccount)
                .equatable()
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .layoutPriority(0)
            FavoriteStarButton(
                isFavorite: isFavorite,
                title: question.displayTitle,
                onToggle: onToggleFavorite
            )
            QuestionRowDateLabel(lastUsed: question.updatedAt)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 24)
        .fixedFastListRowHeight()
        .fastListRowInsets()
    }
}
