//
//  QuestionRow.swift
//  coderpad
//

import SwiftUI

/// A single question row. Owns the row's interactive surface — the hit-test shape,
/// hover, drag, and the favorite button — and embeds the static title/metadata block
/// as an `.equatable()` child (``QuestionRowInfo``). See ``PadRow`` for why only the
/// inert block is memoized, keeping click/selection/drag machinery out of the
/// `EquatableView` (#439).
struct QuestionRow: View {
    let question: Question
    var isFavorite: Bool = false
    /// The owning account's name, shown as a badge only in the combined "All
    /// Accounts" view. `nil` in the normal single-account list.
    var accountName: String?
    /// The owning account's id, so dragging the row onto the sidebar can pin the
    /// question to the right account (the originating one in the merged view).
    var account: UUID?
    var onToggleFavorite: () -> Void = {}

    @State private var hovered = false

    var body: some View {
        #if DEBUG
        let _ = SelectionProfiler.rowTick()
        #endif
        // Drag onto the sidebar Favorites to pin the question (#297). Only when the
        // owning account is known, so the drop can pin it to the right account.
        if let account {
            rowContent.draggable(FavoriteDrop.question(
                account: account,
                id: question.id,
                title: question.displayTitle
            ))
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        // The text/metadata block keeps its top alignment (title, chips, and the
        // last-used date all read from the top), while the favorite star is
        // centered against the row's full height as a row-level action distinct
        // from the metadata.
        HStack(alignment: .center, spacing: 8) {
            QuestionRowInfo(question: question, accountName: accountName)
                .equatable()
            FavoriteStarButton(
                isFavorite: isFavorite,
                hovered: hovered,
                title: question.displayTitle,
                onToggle: onToggleFavorite
            )
        }
        .padding(.vertical, 4)
        // Make the whole row hittable (text, Spacer, empty space) so a click anywhere
        // selects it — on the content HStack, not an EquatableView wrapper, so clicks
        // on the text register too.
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Single click selects/previews the question in the detail pane; double
        // click opens it in its own window. Both are handled natively by the list
        // (selection) and the table's `doubleAction` (open), installed by the owning
        // list — see `TableDoubleClickProxy`. A SwiftUI tap gesture here would break
        // the list's own click-to-select (#324/#326).
    }
}

/// The question row's static title/metadata/date block — the bulk of the row's
/// render cost — memoized via `.equatable()` by ``QuestionRow`` (#439). It holds no
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
