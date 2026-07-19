//
//  AccountEditor+Scopes.swift
//  coderpad
//
//  The post-validation scope probe, split from AccountEditor+Logic.swift to keep both
//  files under the file-length limit.
//

import SwiftUI

extension AccountEditor {
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
        func authorized(_ probe: () async throws -> Void) async -> Bool {
            do {
                try await probe()
                return true
            } catch let error as CoderPadError where error.isUnauthorized {
                return false
            } catch {
                return true
            }
        }
        /// One page proves read access without pulling the whole list.
        func firstPage(_ stream: AsyncThrowingStream<[some Any], any Error>) async throws {
            for try await _ in stream {
                return
            }
        }
        async let padsOK = authorized { try await firstPage(client.listPadsIncrementally()) }
        async let questionsOK = authorized { try await firstPage(client.listQuestionsIncrementally()) }
        async let quotaOK = authorized { _ = try await client.quota() }

        var missing: [String] = []
        if await padsOK == false { missing.append(String(localized: "Pads")) }
        if await questionsOK == false { missing.append(String(localized: "Questions")) }
        if await quotaOK == false { missing.append(String(localized: "Quota")) }
        guard !missing.isEmpty else { return nil }

        // Every probe refused. A key scoped away from all three reads is
        // indistinguishable from one that is simply bad, and calling it "works, but
        // limited" presented a dead key as a successfully validated account with a few
        // empty sections (#2195). Say what the user can act on instead.
        if missing.count == 3 { return Self.allScopesRefusedWarning }

        let list = missing.joined(separator: ", ")
        return String(localized: "This key works, but isn't authorized for: \(list). Those sections may be empty.")
    }

    /// Derives the signed-in user's email from their own pads. `/api/pads/` is scoped
    /// to the API key owner, so the most common owner email on the first page is "you".
    /// Returns nil if the user has no pads yet (e.g. a brand-new account), letting the
    /// caller fall back to the manual picker. Non-fatal: validation already succeeded.
    func detectUserEmail(client: CoderPadClient) async -> String? {
        do {
            for try await page in client.listPadsIncrementally() {
                let emails = page.map(\.ownerEmail).filter { !$0.isEmpty }
                guard !emails.isEmpty else { return nil }

                let counts = Dictionary(emails.map { ($0, 1) }, uniquingKeysWith: +)
                return counts.max { $0.value < $1.value }?.key
            }
        } catch {
            // Ignore: the picker remains available as a fallback.
        }
        return nil
    }
}
