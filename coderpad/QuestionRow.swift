//
//  QuestionRow.swift
//  coderpad
//

import SwiftUI

/// Strings and badges the question row renders, precomputed when the list cache changes
/// rather than while `NSTableView` is recycling hosted SwiftUI cells during scroll.
struct QuestionRowPresentation: Hashable {
    let title: String
    let languageDisplayName: String?
    let interviewType: InterviewType
    let usedLabel: String?
    let isDraft: Bool
    let authorName: String?
    let lastUsedRelative: String?
    let lastUsedTooltip: String?
    let accessibilityLabel: String

    init(question: Question, account: RowAccount?) {
        title = question.displayTitle
        languageDisplayName = question.language.flatMap { language in
            language.isEmpty ? nil : language.coderPadLanguageDisplayName
        }
        interviewType = question.interviewType
        usedLabel = question.used.flatMap { used in
            used > 0 ? String(localized: "Used \(used)×") : nil
        }
        isDraft = question.isDraft == true
        authorName = question.authorName

        if let lastUsed = question.updatedAt {
            let labels = RelativeDateLabel.labels(for: lastUsed)
            lastUsedRelative = labels.relative
            lastUsedTooltip = labels.tooltip
        } else {
            lastUsedRelative = nil
            lastUsedTooltip = nil
        }

        var parts = [title]
        if let account { parts.append(account.name) }
        if let languageDisplayName { parts.append(languageDisplayName) }
        if interviewType == .takeHome { parts.append("Take-home") }
        if let used = question.used, used > 0 { parts.append("used \(used) times") }
        if isDraft { parts.append("Draft") }
        if let authorName { parts.append(authorName) }
        if let lastUsedRelative { parts.append("last used \(lastUsedRelative)") }
        accessibilityLabel = parts.joined(separator: ", ")
    }
}

/// The question row's static title/metadata/date block — the bulk of the row's
/// render cost — memoized via `.equatable()` by ``QuestionRowHostableContent`` (#439). It holds no
/// interaction and no closures, so wrapping it in an `EquatableView` can't affect the
/// row's hit-testing or selection. `==` compares only the fields it renders.
private struct QuestionRowInfo: View, Equatable {
    let presentation: QuestionRowPresentation
    let account: RowAccount?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var expandsForDynamicType: Bool {
        #if os(iOS)
            dynamicTypeSize.isAccessibilitySize
        #else
            false
        #endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation == rhs.presentation && lhs.account == rhs.account
    }

    var body: some View {
        #if DEBUG
            // `let _` is required inside a ViewBuilder (a bare `_ =` isn't a valid
            // builder expression), so silence redundant_discardable_let here.
            // swiftlint:disable:next redundant_discardable_let
            let _ = SelectionProfiler.memoizedTick()
        #endif
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.fastListRowPrimaryLabel)
                    .lineLimit(expandsForDynamicType ? 2 : 1)
                metadata
                authorLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        // Read the title + metadata block as one VoiceOver element with a
        // coherent label (mirroring PadRow), rather than stopping on each chip
        // and label separately; the favorite star stays its own action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var authorLine: some View {
        #if os(macOS)
            Text(presentation.authorName ?? " ")
                .font(.caption)
                .foregroundStyle(Color.fastListRowSecondaryLabel)
                .lineLimit(1)
        #else
            if let author = presentation.authorName {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(expandsForDynamicType ? 2 : 1)
            }
        #endif
    }

    @ViewBuilder
    private var metadata: some View {
        if expandsForDynamicType {
            VStack(alignment: .leading, spacing: 4) {
                metadataItems
            }
        } else {
            HStack(spacing: 8) {
                metadataItems
            }
            .lineLimit(1)
            .clipsMetadataOverflow()
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        #if os(macOS)
            if let account {
                Text(account.name)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
            }
            if let languageDisplayName = presentation.languageDisplayName {
                Text(languageDisplayName)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
            }
            if presentation.interviewType == .takeHome {
                Text(InterviewType.takeHome.label)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
            }
            if let usedLabel = presentation.usedLabel {
                Text(usedLabel)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
            }
            if presentation.isDraft {
                Text("Draft")
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
            }
        #else
            if let account {
                AccountMetaLabel(account: account)
            }
            if let languageDisplayName = presentation.languageDisplayName {
                MetaLabel(text: languageDisplayName)
            }
            if presentation.interviewType == .takeHome {
                InterviewType.takeHome.chip
            }
            if let usedLabel = presentation.usedLabel {
                MetaLabel(text: usedLabel, systemImage: "chart.bar")
            }
            if presentation.isDraft {
                Chip(text: String(localized: "Draft"), systemImage: "doc.badge.ellipsis", tint: .orange)
            }
        #endif
    }
}

/// The question row's right-aligned "last used" date column, mirroring
/// ``PadRowDateLabel`` so the favorite star lands in the same slot on both lists —
/// info, then star, then a fixed date column — rather than the star sitting to the
/// right of the date on questions but to its left on pads (#650). Reserves the shared
/// column width even when a question has never been used so the star stays aligned.
private struct QuestionRowDateLabel: View {
    let relative: String?
    let tooltip: String?

    var body: some View {
        Group {
            if let relative {
                Text(relative)
                    .font(.caption)
                    .foregroundStyle(Color.fastListRowSecondaryLabel)
                    .lineLimit(1)
                    .fixedSize()
                    .help(tooltip.map { "Last used \($0)" } ?? "")
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
    /// Precomputed row strings/badges. The list cache supplies this on macOS hot paths;
    /// falling back keeps previews and incidental call sites correct.
    var presentation: QuestionRowPresentation?
    /// The account this row belongs to, named on the row only in the merged list
    /// (`nil` in the per-account list). (#604)
    var rowAccount: RowAccount?
    /// Resolved by the list owner so the hosted row doesn't read the `@Observable`
    /// favorites store while `NSTableView` recycles cells during scroll (#633).
    var isFavorite: Bool
    /// Toggles the favorite via the owning view's method (which may also clear the
    /// Favorites filter when the last star is removed), rather than the store directly.
    var onToggleFavorite: () -> Void
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        let rowPresentation = presentation ?? QuestionRowPresentation(question: question, account: rowAccount)
        HStack(alignment: .center, spacing: 8) {
            if usesInlineAccountTintRail, let rowAccount {
                AccountTintRail(account: rowAccount)
            }
            QuestionRowInfo(presentation: rowPresentation, account: rowAccount)
                .equatable()
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .layoutPriority(0)
            if usesTrailingFavoriteAction {
                QuestionRowDateLabel(relative: rowPresentation.lastUsedRelative, tooltip: rowPresentation.lastUsedTooltip)
                favoriteButton(title: rowPresentation.title)
            } else {
                favoriteButton(title: rowPresentation.title)
                QuestionRowDateLabel(relative: rowPresentation.lastUsedRelative, tooltip: rowPresentation.lastUsedTooltip)
            }
        }
        .padding(.vertical, 4)
        .padRowTrailingActionInset(enabled: !usesTrailingFavoriteAction)
        .fixedFastListRowHeight()
        .accountTintRailOverlay(rowAccount, enabled: !usesInlineAccountTintRail)
        .fastListRowInsets()
    }

    private func favoriteButton(title: String) -> some View {
        FavoriteStarButton(
            isFavorite: isFavorite,
            title: title,
            onToggle: onToggleFavorite
        )
    }

    private var usesTrailingFavoriteAction: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    private var usesInlineAccountTintRail: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }
}
