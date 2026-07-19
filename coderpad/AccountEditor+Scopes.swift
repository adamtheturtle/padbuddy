//
//  AccountEditor+Scopes.swift
//  coderpad
//
//  The post-validation scope probe, split from AccountEditor+Logic.swift to keep both
//  files under the file-length limit.
//

import SwiftUI

extension AccountEditor {
    enum ScopeProbeError: Error {
        case emptyResponse
    }

    enum ScopeProbeResult: Equatable {
        case authorized
        case refused
        case unknown
    }

    /// After the key proves it can reach the org, probe the main read endpoints
    /// with one lightweight request each and report any that return a 403, so the
    /// user learns up front that, e.g., Questions will be empty rather than hitting
    /// a silent empty section later. Non-blocking: the account still validates and
    /// saves. Network/other errors are not treated as missing scopes.
    /// Shown when the key reached the organization but every read endpoint refused it.
    static let allScopesRefusedWarning = String(localized: """
    This key reached your organization but was refused for pads, questions, and quota. \
    It may be expired or scoped too narrowly to be useful \u{2014} check it in CoderPad.
    """)

    func missingScopesWarning(client: CoderPadClient) async -> String? {
        // Probe sequentially: validation is already complete and these optional
        // capability checks must not burst three requests at a newly added,
        // self-hosted, or rate-limited server (#1400).
        let pads = await Self.scopeProbeResult { try await Self.requireFirstPage(client.listPadsIncrementally()) }
        let questions = await Self.scopeProbeResult {
            try await Self.requireFirstPage(client.listQuestionsIncrementally())
        }
        let quota = await Self.scopeProbeResult { _ = try await client.quota() }

        let probes = [(String(localized: "Pads"), pads),
                      (String(localized: "Questions"), questions),
                      (String(localized: "Quota"), quota)]
        let refused = probes.filter { $0.1 == .refused }.map(\.0)
        let unknown = probes.filter { $0.1 == .unknown }.map(\.0)
        guard !refused.isEmpty || !unknown.isEmpty else { return nil }

        // Every probe refused. A key scoped away from all three reads is
        // indistinguishable from one that is simply bad, and calling it "works, but
        // limited" presented a dead key as a successfully validated account with a few
        // empty sections (#2195). Say what the user can act on instead.
        if refused.count == 3 { return Self.allScopesRefusedWarning }

        var warnings: [String] = []
        if !refused.isEmpty {
            let list = refused.joined(separator: ", ")
            warnings.append(String(localized: "This key works, but isn't authorized for: \(list)."))
        }
        if !unknown.isEmpty {
            let list = unknown.joined(separator: ", ")
            warnings.append(String(localized: "Couldn't verify access to: \(list). Those sections may be unavailable."))
        }
        return warnings.joined(separator: " ")
    }

    static func scopeProbeResult(_ probe: () async throws -> Void) async -> ScopeProbeResult {
        do {
            try await probe()
            return .authorized
        } catch let error as CoderPadError where error.isUnauthorized {
            return .refused
        } catch {
            return .unknown
        }
    }

    /// One yielded page proves the endpoint actually completed a response. A stream
    /// that ends before yielding cannot be treated as evidence of authorization.
    static func requireFirstPage<Element>(_ stream: AsyncThrowingStream<[Element], any Error>) async throws {
        for try await _ in stream {
            return
        }
        throw ScopeProbeError.emptyResponse
    }

    /// Derives the signed-in user's email from their own pads. `/api/pads/` is scoped
    /// to the API key owner, so the most common owner email on the first page is "you".
    /// Returns nil if the user has no pads yet (e.g. a brand-new account), letting the
    /// caller fall back to the manual picker. Non-fatal: validation already succeeded.
    /// How many streamed pages the owner detection will look at.
    ///
    /// It used to decide on the first page alone, and bail entirely if that page
    /// happened to carry no owner emails — so an account whose own pads were not in
    /// the first page got the wrong owner, or none (#2196). Bounded rather than
    /// exhaustive because this runs during validation: a few pages is plenty to find
    /// the dominant owner, and paging a whole org here would stall the flow.
    private static let detectionPageLimit = 5

    func detectUserEmail(client: CoderPadClient) async -> String? {
        var counts: [String: Int] = [:]
        var pagesScanned = 0
        do {
            for try await page in client.listPadsIncrementally() {
                for email in page.map(\.ownerEmail) where !email.isEmpty {
                    counts[email, default: 0] += 1
                }
                pagesScanned += 1
                if pagesScanned >= Self.detectionPageLimit { break }
            }
        } catch {
            // Ignore: whatever was counted so far still stands, and the picker remains
            // available as a fallback.
        }
        // Ties break on the address so the result is stable rather than dependent on
        // dictionary ordering.
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}
