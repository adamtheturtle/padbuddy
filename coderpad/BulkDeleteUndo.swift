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

/// How far through a committed batch the deletes have got, so a large selection
/// shows progress and a stop control instead of an unexplained pause (#2347).
struct BulkDeleteProgress: Equatable {
    var completed: Int
    var total: Int

    var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

enum BulkDeleteUndo {
    static let gracePeriod: Duration = .seconds(5)

    /// How many deletes are in flight at once. Destructive requests are not fired all
    /// at once - that invites rate limiting on a large selection, and rate-limit
    /// failures are indistinguishable from real ones - but issuing them strictly one
    /// at a time made a fifty-item batch take the better part of a minute (#2342).
    static let concurrency = 4

    /// Whether a failure means every remaining delete in the batch would fail too.
    /// Continuing past one of these issues dozens of requests that cannot succeed and
    /// buries the real cause under a list of identical failures (#2346).
    static func isSystemic(_ error: any Error) -> Bool {
        if (error as? CoderPadError)?.isUnauthorized == true { return true }
        guard let urlError = error as? URLError else { return false }

        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// The report for a batch abandoned after a systemic failure: it names how many
    /// were never attempted, which is the part a user has to act on.
    static func abortedReport(deleted: Int, total: Int, error: String) -> String {
        String(localized: "Stopped after deleting \(deleted) of \(total). \(error)")
    }

    /// What a batch was deleting, for the aggregated report.
    enum Kind {
        case pads, questions
    }

    static let credentialsChangedReport = String(localized: """
    Didn't delete anything: this account's credentials changed while the undo window was open.
    """)

    /// Whether the account a batch was scheduled under is still configured and still
    /// points at the same backend with the same key (#2344, #1258). A batch with no
    /// resolvable owning account was scheduled against an ad-hoc client the account
    /// store never owned, so there is nothing to invalidate.
    @MainActor
    static func accountStillUsable(_ owning: Account?, in accounts: AccountsStore) -> Bool {
        guard let owning else { return true }
        guard let current = accounts.accounts.first(where: { $0.id == owning.id }) else { return false }

        return !current.pointsAtDifferentBackend(than: owning)
    }

    /// The one aggregated report for a finished batch, or nil when everything
    /// succeeded. A batch stopped early by a systemic failure says how many were never
    /// attempted rather than implying the rest succeeded (#2346).
    static func report(_ outcome: BulkDeleteRunner.Outcome, total: Int, kind: Kind) -> String? {
        guard let lastError = outcome.lastError else { return nil }
        guard !outcome.aborted else {
            return abortedReport(deleted: outcome.deleted, total: total, error: lastError)
        }

        return switch kind {
        case .pads:
            padFailureReport(failedTitles: outcome.failedTitles, total: total, lastError: lastError)
        case .questions:
            questionFailureReport(failedTitles: outcome.failedTitles, total: total, lastError: lastError)
        }
    }

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
                .prominentActionButtonStyle()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCapsule()
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

/// Shown once a batch is committed and the deletes are actually running, replacing
/// the undo banner. Before this the banner simply vanished and a long batch looked
/// like nothing was happening, with no way to stop it partway (#2347).
struct BulkDeleteProgressBanner: View {
    let progress: BulkDeleteProgress
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Deleting \(progress.completed) of \(progress.total)…")
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: 8)
            // Stop, not Undo: what has already been deleted is gone. This only
            // prevents the requests that have not been issued yet.
            Button("Stop", action: onStop)
                .prominentActionButtonStyle()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCapsule()
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Runs one committed batch: bounded concurrency (#2342), progress reporting
/// (#2347), and an early stop once a failure proves the rest cannot succeed (#2346).
/// The four bulk-delete sites differ only in how an item is deleted and titled, so
/// they share this rather than each growing their own copy of the loop.
@MainActor
enum BulkDeleteRunner {
    struct Outcome {
        var failedTitles: [String] = []
        var lastError: String?
        /// True when a systemic failure stopped the batch early, so the report can say
        /// how many were never attempted rather than implying they all succeeded.
        var aborted = false
        var deleted = 0
    }

    /// - Parameters:
    ///   - delete: performs one item's delete; throwing records a failure.
    ///   - onProgress: called after each item settles.
    static func run<Item: Sendable>(
        _ items: [Item],
        title: (Item) -> String,
        onProgress: (BulkDeleteProgress) -> Void,
        // Main-actor isolated, like everything it touches (the account store, the
        // caches, the router). The deletes are network-bound, so a chunk's requests
        // still overlap properly while suspended.
        delete: @MainActor @escaping (Item) async -> (any Error)?
    ) async -> Outcome {
        var outcome = Outcome()
        let titles = items.map(title)
        var completed = 0
        onProgress(BulkDeleteProgress(completed: 0, total: items.count))

        var index = 0
        while index < items.count {
            // Cancellation is the user's Stop, or the view going away (#1257).
            guard !Task.isCancelled else { break }

            let upper = min(index + BulkDeleteUndo.concurrency, items.count)
            let chunk = (index ..< upper).map { position in
                let item = items[position]
                return (position, Task { @MainActor in await delete(item) })
            }
            for (position, task) in chunk {
                let error = await task.value
                completed += 1
                if let error {
                    outcome.failedTitles.append(titles[position])
                    outcome.lastError = error.localizedDescription
                    if BulkDeleteUndo.isSystemic(error) { outcome.aborted = true }
                } else {
                    outcome.deleted += 1
                }
                onProgress(BulkDeleteProgress(completed: completed, total: items.count))
            }
            // Nothing after a systemic failure can succeed, so the queue is dropped
            // rather than issuing dozens more requests that cannot work (#2346).
            if outcome.aborted { break }

            index = upper
        }
        return outcome
    }
}
