//
//  WidgetHandoffRequests.swift
//  coderpad
//
//  The app's side of the widget handoff queue: recording New Pad / Open Pad
//  requests and draining them in issue order. Split from WidgetPadSnapshot.swift
//  to keep both files under the file-length limit. Mirrors the extension's copy in
//  `RecentPadsWidget/WidgetSharedSnapshot.swift` — the two must stay in lock-step.
//

import Foundation
import OSLog

/// `nonisolated` is not inherited by an extension in another file, and these are
/// called from the widget/Control Center intents off the main actor.
nonisolated extension WidgetSharedStore {
    static var maxPendingRequests: Int {
        100
    }

    static func pendingRequestFilesToRemove(_ names: [String], reserving slots: Int = 1) -> [String] {
        let pending = names.filter {
            ($0.hasPrefix(newPadRequestPrefix) || $0.hasPrefix(openPadRequestPrefix))
                && $0.hasSuffix(requestFileExtension)
        }.sorted {
            let lhs = requestOrdinal(fileName: $0), rhs = requestOrdinal(fileName: $1)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        let keep = max(0, maxPendingRequests - max(0, slots))
        return Array(pending.prefix(max(0, pending.count - keep)))
    }

    private static func reservePendingRequestSlot() {
        guard let container = containerURL(purpose: pendingRequestsPurpose),
              let names = try? FileManager.default.contentsOfDirectory(atPath: container.path) else { return }

        for name in pendingRequestFilesToRemove(names) {
            try? FileManager.default.removeItem(at: container.appending(path: name))
        }
    }

    // Records a New Pad request for the app to pick up on its next activation, written
    // as a file (not `UserDefaults`) so it's seen immediately across the App Group with
    // no suite-cache delay. Idempotent: `takePendingRequestsInOrder` is the single
    // consumer and deletes the file, so re-recording before consumption is harmless.
    // A no-op when the container is unavailable. Mirrors the widget target's copy
    // (`RecentPadsWidget/WidgetSharedSnapshot.swift`); it lives here too so the app-target
    // twin of `CreatePadIntent` — the one that lets the Control Center button open the
    // app (#485) — compiles against it.

    /// The widest pad id worth queueing. Real ids are short slugs; anything longer can
    /// only be malformed configuration, and persisting it just fills the App Group with
    /// a request nothing can route (#2364).
    static var maxHandoffPadIDLength: Int {
        64
    }

    /// Mirrors `PadIDValidation` without depending on app-target code unavailable
    /// to the widget extension. Pad IDs cannot contain URL structure characters.
    static func validatedHandoffPadID(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... maxHandoffPadIDLength).contains(trimmed.count),
              trimmed.allSatisfy({ character in
                  character == "-" || character == "_"
                      || (character.isASCII && (character.isLetter || character.isNumber))
              }) else { return nil }

        return trimmed
    }

    /// `.some(nil)` for a request that names no account (create in whichever is
    /// current), `.some(id)` for a well-formed one, and nil when the string is present
    /// but is not an account identifier — which the caller refuses outright (#2364).
    static func validatedAccount(_ account: String?) -> String?? {
        guard let account else { return .some(nil) }

        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        if let uuid = UUID(uuidString: trimmed) { return .some(uuid.uuidString) }
        guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }

        return .some(trimmed.lowercased())
    }

    @discardableResult
    static func requestNewPad(account: String?, question: Int?, requestID: UUID = UUID()) -> Bool {
        // CoderPad question ids are positive. A zero or negative one can only have
        // come from malformed configuration, and seeding the create flow with it
        // produces a request the server rejects, so drop the seed and let the flow
        // open unseeded rather than failing (#2595).
        let seed = question.flatMap { $0 > 0 ? $0 : nil }
        if question != nil, seed == nil {
            logger.error("Dropped a non-positive question seed from a new pad handoff request")
        }
        // The account travels as a string, so a stale or hand-edited configuration can
        // carry something that is not an account id at all. It used to be persisted and
        // only rejected at the far end, where the request was silently dropped; refusing
        // it here means an unusable request is never queued (#2364). A seed is scoped to
        // its account, so it cannot outlive one that failed to parse.
        guard let owner = validatedAccount(account) else {
            logger.error("Refused a new pad handoff request with a malformed account identifier")
            return false
        }

        if hasPendingNewPadRequest(requestID) { return true }

        reservePendingRequestSlot()
        guard save(WidgetNewPadRequest(account: owner, question: owner == nil ? nil : seed, id: requestID),
                   fileName: requestFileName(prefix: newPadRequestPrefix),
                   purpose: newPadPurpose) else {
            return false
        }

        postNewPadRequestNotification()
        logger.info("""
        Recorded new pad handoff request accountScoped=\((account?.isEmpty == false), privacy: .public) \
        questionSeeded=\(question != nil, privacy: .public)
        """)
        return true
    }

    private static func hasPendingNewPadRequest(_ id: UUID) -> Bool {
        pendingRequestURLs(purpose: pendingRequestsPurpose).contains { candidate in
            guard candidate.isNewPad,
                  let data = try? Data(contentsOf: candidate.url),
                  let request = try? decoder.decode(WidgetNewPadRequest.self, from: data)
            else { return false }

            return request.id == id
        }
    }

    /// Records an iPad widget recent-pad tap for the app to route after the intent opens it.
    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        // An empty id can only produce a handoff the app cannot act on: it would be
        // drained, consumed, and silently do nothing, with no way for the user to
        // retry (#2594). Refuse it at the source instead.
        guard let padID = validatedHandoffPadID(id) else {
            logger.error("Refused an open pad handoff request with an empty or malformed pad id")
            return false
        }
        guard let owner = validatedAccount(account) else {
            logger.error("Refused an open pad handoff request with a malformed account identifier")
            return false
        }

        reservePendingRequestSlot()
        guard save(WidgetOpenPadRequest(id: padID, account: owner),
                   fileName: requestFileName(prefix: openPadRequestPrefix),
                   purpose: openPadPurpose) else {
            return false
        }

        postOpenPadRequestNotification()
        logger.info("Recorded open pad handoff request accountScoped=\((account?.isEmpty == false), privacy: .public)")
        return true
    }

    /// Nudges a running app to drain the just-recorded request right away.
    /// `applicationDidBecomeActive` covers cold launch and background→foreground, but
    /// not the case where the app is already frontmost (a control/widget tap then causes
    /// no activation transition), so post a Darwin notification the app observes to drain
    /// regardless of its activation state (#485). Cross-process and payload-free by design.
    private static func postNewPadRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(newPadRequestNotification as CFString),
            nil, nil, true
        )
    }

    private static func postOpenPadRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(openPadRequestNotification as CFString),
            nil, nil, true
        )
    }

    /// Whether a filename names a new-pad request (`true`), an open-pad request
    /// (`false`), or neither (`nil`). Both the legacy fixed names and the timestamped
    /// ones are recognized.
    static func isNewPadRequest(fileName: String) -> Bool? {
        if fileName == newPadRequestFile { return true }
        if fileName == openPadRequestFile { return false }
        guard fileName.hasSuffix(requestFileExtension) else { return nil }

        if fileName.hasPrefix(newPadRequestPrefix) { return true }
        if fileName.hasPrefix(openPadRequestPrefix) { return false }

        return nil
    }

    /// Extracts the original pending filename from a typed claim. Older releases
    /// used opaque `claimed-<UUID>.json` names; those cannot be replayed safely
    /// because their request kind and ordering were discarded.
    static func claimedRequestOriginalName(_ fileName: String) -> String? {
        guard fileName.hasPrefix(claimedRequestPrefix) else { return nil }

        let remainder = fileName.dropFirst(claimedRequestPrefix.count)
        guard remainder.count > 37 else { return nil }

        let uuidText = String(remainder.prefix(36))
        guard UUID(uuidString: uuidText) != nil, remainder.dropFirst(36).first == "-" else { return nil }

        let original = String(remainder.dropFirst(37))
        return isNewPadRequest(fileName: original) == nil ? nil : original
    }

    static func abandonedClaimOriginalName(fileName: String, age: TimeInterval) -> String? {
        guard age > abandonedClaimLifetime else { return nil }

        return claimedRequestOriginalName(fileName)
    }

    /// Restores crash-abandoned typed claims to their original pending names. The
    /// move is atomic: concurrent app activations may both discover a claim, but
    /// only one can restore it and the normal rename-to-claim race then guarantees
    /// one consumer (#1079).
    private static func recoverAbandonedClaims(in container: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: container, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }

        let now = Date()
        for claimed in urls {
            let values = try? claimed.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true else { continue }

            let modified = values?.contentModificationDate ?? now
            guard let original = abandonedClaimOriginalName(
                fileName: claimed.lastPathComponent,
                age: now.timeIntervalSince(modified)
            ) else { continue }

            let restored = container.appending(path: original, directoryHint: .notDirectory)
            try? FileManager.default.moveItem(at: claimed, to: restored)
        }
    }

    /// Every pending request file in the shared container, tagged by kind. One
    /// listing covers both kinds: this runs on activation and on every Darwin
    /// notification, and asking per kind enumerated the App Group directory twice
    /// each time (#2138).
    static func pendingRequestURLs(purpose: String) -> [(url: URL, isNewPad: Bool)] {
        guard let container = containerURL(purpose: purpose) else { return [] }

        do {
            recoverAbandonedClaims(in: container)
            return try FileManager.default
                .contentsOfDirectory(at: container, includingPropertiesForKeys: [.isRegularFileKey])
                .compactMap { url in
                    guard let isNewPad = isNewPadRequest(fileName: url.lastPathComponent) else { return nil }

                    // Name-matching alone would also pick up a directory or a symlink
                    // sitting in the App Group, which the drain would then try to claim,
                    // move, and decode (#2183). Only a regular file is a request.
                    guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                    else { return nil }

                    return (url: url, isNewPad: isNewPad)
                }
        } catch {
            logger.error("""
            Widget shared store list failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
            return []
        }
    }

    /// Drops any queued New Pad / Open Pad request naming `account`.
    ///
    /// Removing an account cleared its snapshots but left its queued handoffs behind,
    /// so a drain after the removal routed a create or open against an account that no
    /// longer exists (#2187). Requests naming a different account, or none at all, are
    /// untouched.
    static func discardPendingRequests(account: String) {
        let owner = validatedAccount(account).flatMap(\.self)
        guard let owner else { return }

        let candidates = pendingRequestURLs(purpose: pendingRequestsPurpose)

        var discarded = 0
        for candidate in candidates {
            guard let data = loadData(url: candidate.url, purpose: newPadPurpose) else { continue }

            let named: String? = if candidate.isNewPad {
                (try? decoder.decode(WidgetNewPadRequest.self, from: data))?.account
            } else {
                (try? decoder.decode(WidgetOpenPadRequest.self, from: data))?.account
            }
            guard named == owner else { continue }

            try? FileManager.default.removeItem(at: candidate.url)
            discarded += 1
        }
        if discarded > 0 {
            logger.info("""
            Discarded \(discarded, privacy: .public) pending widget requests for a removed account
            """)
        }
    }

    /// The most requests one drain will replay. See `takePendingRequestsInOrder`.
    static let maxDrainedRequests = 10

    /// Returns and clears every pending widget/Shortcuts request, of both kinds, in
    /// the order the user issued them. The request filenames embed a millisecond
    /// timestamp, so a single combined drain can replay them chronologically and the
    /// user's most recent action ends up on top (#1045). Empty when none is pending.
    static func takePendingRequestsInOrder() -> [WidgetPendingRequest] {
        let candidates = pendingRequestURLs(purpose: pendingRequestsPurpose)

        // Stale requests are discarded rather than replayed. A tap recorded days ago
        // creating or opening a pad on a much later launch is surprising and
        // unattributable (#2179). The sweep applies the same lifetime, but the drain
        // cannot depend on the sweep having run first.
        let now = Date()
        let fresh = candidates.filter { candidate in
            guard let modified = (try? candidate.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { return true }
            guard now.timeIntervalSince(modified) <= pendingRequestLifetime else {
                try? FileManager.default.removeItem(at: candidate.url)
                return false
            }

            return true
        }

        let ordered = fresh
            .sorted {
                (requestOrdinal(fileName: $0.url.lastPathComponent), $0.url.lastPathComponent)
                    < (requestOrdinal(fileName: $1.url.lastPathComponent), $1.url.lastPathComponent)
            }
        // Bounded: repeated taps (a stuck button, a burst of impatient presses) would
        // otherwise all replay at once as a startup flood of sheets and windows
        // (#2180). The newest are kept, since the most recent action is what the user
        // is actually waiting for, and the rest are dropped rather than left to replay
        // on the next launch.
        let excess = max(0, ordered.count - maxDrainedRequests)
        for candidate in ordered.prefix(excess) {
            try? FileManager.default.removeItem(at: candidate.url)
        }
        if excess > 0 {
            logger.error("Dropped \(excess, privacy: .public) queued widget requests over the drain cap")
        }

        let decoded: [WidgetPendingRequest] = ordered
            .suffix(maxDrainedRequests)
            .compactMap { candidate in
                if candidate.isNewPad {
                    return takeRequest(at: candidate.url, purpose: newPadPurpose, as: WidgetNewPadRequest.self)
                        .map(WidgetPendingRequest.newPad)
                }
                return takeRequest(at: candidate.url, purpose: openPadPurpose, as: WidgetOpenPadRequest.self)
                    .map(WidgetPendingRequest.openPad)
            }
        let requests = deduplicatingNewPadRequests(decoded)
        if !requests.isEmpty {
            logger.info("Drained \(requests.count, privacy: .public) pending widget requests in order")
        }
        return requests
    }

    static func deduplicatingNewPadRequests(_ requests: [WidgetPendingRequest]) -> [WidgetPendingRequest] {
        var seen = Set<UUID>()
        return requests.filter { request in
            guard case let .newPad(newPad) = request else { return true }

            return seen.insert(newPad.id).inserted
        }
    }
}
