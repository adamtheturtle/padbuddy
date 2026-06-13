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
    var onToggleFavorite: () -> Void = {}

    @State private var hovered = false

    var body: some View {
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
                    HStack(spacing: 6) {
                        if let accountName {
                            Chip(text: accountName, systemImage: "person.crop.circle", tint: .purple)
                        }
                        if let lang = question.language, !lang.isEmpty {
                            Chip(text: lang.languageDisplayName)
                        }
                        if question.interviewType == .takeHome {
                            InterviewType.takeHome.chip
                        }
                        if let used = question.used, used > 0 {
                            Chip(text: "Used \(used)×", systemImage: "chart.bar", tint: .blue)
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
                        .help("Last used \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityLabel("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                }
            }
            favoriteButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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
