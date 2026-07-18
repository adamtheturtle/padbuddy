//
//  BulkDeleteUndo.swift
//  coderpad
//

import SwiftUI

struct PendingBulkDelete<Item>: Identifiable {
    let id = UUID()
    let items: [Item]
    let message: String
}

enum BulkDeleteUndo {
    static let gracePeriod: Duration = .seconds(5)

    static func mergedItems<Item: Identifiable>(
        existing: [Item],
        adding newItems: [Item]
    ) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        var merged = existing
        for item in newItems where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    /// A short enumeration of the pending items' titles, so the undo banner spells
    /// out exactly what a (possibly merged) batch will delete rather than only a
    /// count — a second confirmed batch merges into the first, and the user must be
    /// able to see everything a single Undo now covers (#1260).
    static func summary(of titles: [String], limit: Int = 3) -> String {
        let cleaned = titles.map { title in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
        }
        let shown = cleaned.prefix(limit).joined(separator: ", ")
        let remaining = cleaned.count - limit
        return remaining > 0 ? String(localized: "\(shown) and \(remaining) more") : shown
    }

    /// One aggregated, actionable report for a partly failed batch: which items
    /// remain, out of how many, and the underlying error — instead of each failure
    /// silently overwriting the previous one in a single error slot (#1256, #1208).
    static func padFailureReport(failedTitles: [String], total: Int, lastError: String) -> String {
        String(localized: """
        Couldn't delete \(failedTitles.count) of ^[\(total) pads](inflect: true): \
        \(summary(of: failedTitles)). \(lastError)
        """)
    }

    static func questionFailureReport(failedTitles: [String], total: Int, lastError: String) -> String {
        String(localized: """
        Couldn't delete \(failedTitles.count) of ^[\(total) questions](inflect: true): \
        \(summary(of: failedTitles)). \(lastError)
        """)
    }
}

struct BulkDeleteUndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .accessibilityHidden(true)
            Text(message)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, 12)
        .onAppear { announce() }
        .onChange(of: message) { announce() }
    }

    /// VoiceOver users can miss the transient banner entirely — it's the only undo
    /// opportunity before a destructive action executes — so the pending batch and
    /// its expiring undo window are announced explicitly, and re-announced whenever
    /// a merged batch changes the message (#1261).
    private func announce() {
        let seconds = BulkDeleteUndo.gracePeriod.components.seconds
        AccessibilityNotification.Announcement(
            String(localized: "\(message) Undo available for the next \(seconds) seconds.")
        ).post()
    }
}
