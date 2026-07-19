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
    /// Records a New Pad request for the app to pick up on its next activation, written
    /// as a file (not `UserDefaults`) so it's seen immediately across the App Group with
    /// no suite-cache delay. Idempotent: `takePendingRequestsInOrder` is the single
    /// consumer and deletes the file, so re-recording before consumption is harmless.
    /// A no-op when the container is unavailable. Mirrors the widget target's copy
    /// (`RecentPadsWidget/WidgetSharedSnapshot.swift`); it lives here too so the app-target
    /// twin of `CreatePadIntent` — the one that lets the Control Center button open the
    /// app (#485) — compiles against it.
    @discardableResult
    static func requestNewPad(account: String?, question: Int?) -> Bool {
        // CoderPad question ids are positive. A zero or negative one can only have
        // come from malformed configuration, and seeding the create flow with it
        // produces a request the server rejects, so drop the seed and let the flow
        // open unseeded rather than failing (#2595).
        let seed = question.flatMap { $0 > 0 ? $0 : nil }
        if question != nil, seed == nil {
            logger.error("Dropped a non-positive question seed from a new pad handoff request")
        }
        guard save(WidgetNewPadRequest(account: account, question: seed),
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

    /// Records an iPad widget recent-pad tap for the app to route after the intent opens it.
    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        // An empty id can only produce a handoff the app cannot act on: it would be
        // drained, consumed, and silently do nothing, with no way for the user to
        // retry (#2594). Refuse it at the source instead.
        let padID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !padID.isEmpty else {
            logger.error("Refused an open pad handoff request with an empty pad id")
            return false
        }
        guard save(WidgetOpenPadRequest(id: padID, account: account),
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

    /// Returns and clears every pending widget/Shortcuts request, of both kinds, in
    /// the order the user issued them. The request filenames embed a millisecond
    /// timestamp, so a single combined drain can replay them chronologically and the
    /// user's most recent action ends up on top (#1045). Empty when none is pending.
    static func takePendingRequestsInOrder() -> [WidgetPendingRequest] {
        let candidates = pendingRequestURLs(
            legacyFileName: newPadRequestFile, prefix: newPadRequestPrefix, purpose: newPadPurpose
        ).map { (url: $0, isNewPad: true) } + pendingRequestURLs(
            legacyFileName: openPadRequestFile, prefix: openPadRequestPrefix, purpose: openPadPurpose
        ).map { (url: $0, isNewPad: false) }

        let requests: [WidgetPendingRequest] = candidates
            .sorted {
                (requestOrdinal(fileName: $0.url.lastPathComponent), $0.url.lastPathComponent)
                    < (requestOrdinal(fileName: $1.url.lastPathComponent), $1.url.lastPathComponent)
            }
            .compactMap { candidate in
                if candidate.isNewPad {
                    return takeRequest(at: candidate.url, purpose: newPadPurpose, as: WidgetNewPadRequest.self)
                        .map(WidgetPendingRequest.newPad)
                }
                return takeRequest(at: candidate.url, purpose: openPadPurpose, as: WidgetOpenPadRequest.self)
                    .map(WidgetPendingRequest.openPad)
            }
        if !requests.isEmpty {
            logger.info("Drained \(requests.count, privacy: .public) pending widget requests in order")
        }
        return requests
    }
}
