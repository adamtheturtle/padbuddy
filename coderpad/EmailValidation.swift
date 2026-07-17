//
//  EmailValidation.swift
//  coderpad
//
//  Shared lightweight email plausibility checks for user-entered account/member and
//  invitation addresses. This is intentionally not full RFC validation; it rejects
//  obvious malformed values before they are saved or sent to the API.
//

import Foundation

enum EmailValidation {
    /// A light plausibility check: one @, a non-empty local part, a dotted domain,
    /// and no whitespace.
    static func isPlausibleAddress(_ value: String) -> Bool {
        guard !value.contains(where: \.isWhitespace) else { return false }

        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }

        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
