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
    let accountName: String?

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
            && lhs.accountName == rhs.accountName
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
                    if let accountName {
                        MetaLabel(text: accountName, systemImage: "person.crop.circle")
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
                if let author = question.authorName {
                    Text(author).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let lastUsed = question.updatedAt {
                // Cached labels rather than `.formatted` per render — see PadRow (#439).
                let labels = RelativeDateLabel.labels(for: lastUsed)
                Text(labels.relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Last used \(labels.tooltip)")
                    .accessibilityLabel("Last used \(labels.relative)")
            }
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
        if let accountName { parts.append(accountName) }
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

/// The question row as hosted inside the `NSTableView`-backed `ListTable` (#439). The
/// title/metadata block is `.allowsHitTesting(false)` so left-clicks pass through the
/// `NSHostingView` to the table for native selection; only the favorite star stays
/// hittable. Mirrors ``PadRowHostableContent``. Selection, double-click, swipe, drag,
/// and the context menu are the table's job.
struct QuestionRowHostableContent: View {
    let question: Question
    var accountName: String?
    /// The owning account, used to read the favorite state.
    var account: UUID?
    /// Read live in `body` (it's `@Observable`) so toggling the star re-renders the
    /// hosted row immediately — the cell isn't otherwise re-created on a favorite change.
    var favorites: FavoriteQuestionsStore
    /// Toggles the favorite via the owning view's method (which may also clear the
    /// Favorites filter when the last star is removed), rather than the store directly.
    var onToggleFavorite: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            QuestionRowInfo(question: question, accountName: accountName)
                .equatable()
                .allowsHitTesting(false)
            FavoriteStarButton(
                isFavorite: favorites.isFavorite(question.id, account: account),
                hovered: hovered,
                title: question.displayTitle,
                onToggle: onToggleFavorite
            )
        }
        .padding(.vertical, 4)
        .onHover { hovered = $0 }
    }
}
