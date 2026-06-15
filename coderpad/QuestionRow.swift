//
//  QuestionRow.swift
//  coderpad
//

import SwiftUI

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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
                            MetaLabel(text: "Used \(used)×", systemImage: "chart.bar")
                        }
                        if question.isDraft == true {
                            Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                        }
                    }
                    if let author = question.authorName {
                        Text(author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let lastUsed = question.updatedAt {
                    Text(lastUsed.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Last used \(lastUsed.formatted(date: .long, time: .shortened))")
                        .accessibilityLabel("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                }
            }
            // Read the title + metadata block as one VoiceOver element with a
            // coherent label (mirroring PadRow), rather than stopping on each chip
            // and label separately; the favorite star stays its own action.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            favoriteButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Single click selects/previews the question in the detail pane (handled
        // natively by the list), double click opens it in its own window — the macOS
        // convention, matching the companion pad gesture (#292). Double-click is
        // caught with a non-delaying AppKit recognizer rather than a SwiftUI tap
        // gesture, which would otherwise swallow the list's click-to-select
        // (#324/#326).
        .onRowDoubleClick {
            openWindow(id: "question", value: QuestionWindowID(account: account, id: question.id))
        }
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
            parts.append("last used \(lastUsed.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: ", ")
    }

    /// Inline favorite toggle, à la Mail's flag: always shown (filled) once the
    /// question is starred, and revealed faintly on hover otherwise so the resting
    /// list stays uncluttered. The button always occupies its slot — only opacity
    /// changes on hover — so rows don't shift as the pointer moves down the list.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || hovered ? 1 : 0)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(question.displayTitle) from Favorites"
            : "Add \(question.displayTitle) to Favorites")
    }
}
