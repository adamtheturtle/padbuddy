//
//  EmailValidation.swift
//  coderpad
//
//  Shared lightweight email plausibility checks for user-entered account/member and
//  invitation addresses. This is intentionally not full RFC validation (quoted local
//  parts and address literals are rejected); it rejects obvious malformed values
//  before they are saved or sent to the API.
//

import Foundation

enum EmailValidation {
    /// A light plausibility check: one @, a valid unquoted local part, a dotted
    /// domain of non-empty labels, and no whitespace or control/format characters
    /// anywhere (#1940).
    static func isPlausibleAddress(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isWhitespace || isControlOrFormat($0) }) else { return false }

        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        return isPlausibleLocalPart(parts[0]) && isPlausibleDomain(parts[1])
    }

    /// The address trimmed, with its case-insensitive domain lowercased, so the same
    /// mailbox entered with different casing stores and compares consistently
    /// (#1941). The local part's case is preserved: its semantics belong to the
    /// receiving server.
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.lastIndex(of: "@") else { return trimmed }

        let domain = trimmed[trimmed.index(after: atIndex)...].lowercased()
        return "\(trimmed[..<atIndex])@\(domain)"
    }

    /// The symbols RFC 5322 allows in an unquoted local part, besides letters,
    /// digits, and interior dots (#1939).
    private static let localPartSymbols = Set("!#$%&'*+-/=?^_`{|}~")

    private static func isPlausibleLocalPart(_ local: Substring) -> Bool {
        guard !local.isEmpty, !local.hasPrefix("."), !local.hasSuffix("."),
              !local.contains("..") else { return false }

        return local.allSatisfy { $0 == "." || $0.isLetter || $0.isNumber || localPartSymbols.contains($0) }
    }

    /// Non-empty dot-separated labels (so consecutive dots are rejected, #1938) of
    /// letters/digits/hyphens without leading or trailing hyphens; at least two
    /// labels, since a bare hostname isn't a plausible public address.
    private static func isPlausibleDomain(_ domain: Substring) -> Bool {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        return labels.allSatisfy { label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    /// Whitespace checks miss non-printing scalars like NUL or zero-width joiners;
    /// an address carrying any control/format character is not plausible (#1940).
    private static func isControlOrFormat(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let category = scalar.properties.generalCategory
            return category == .control || category == .format
        }
    }
}
