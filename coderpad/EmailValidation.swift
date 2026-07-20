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

nonisolated enum EmailValidation {
    /// A light plausibility check: one @, a valid unquoted local part, a dotted
    /// domain of non-empty labels, and no whitespace or control/format characters
    /// anywhere (#1940).
    static func isPlausibleAddress(_ value: String) -> Bool {
        // One pass that both rejects whitespace/control-format characters and finds
        // the @, rather than walking the string once per check. The general-category
        // lookup is a genuinely costly Unicode query, so it sits behind an ASCII test:
        // no ASCII character above the control range is control-or-format, and this
        // runs per keystroke (#2258).
        var atIndex: String.Index?
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character.isWhitespace { return false }
            if !character.isASCII, isControlOrFormat(character) { return false }
            if character.isASCII, let ascii = character.asciiValue, ascii < 0x20 || ascii == 0x7F {
                return false
            }
            if character == "@" {
                // A second @ makes the address implausible, exactly as the old
                // two-component split did.
                if atIndex != nil { return false }

                atIndex = index
            }
            index = value.index(after: index)
        }
        guard let atIndex else { return false }

        return isPlausibleLocalPart(value[value.startIndex ..< atIndex])
            && isPlausibleDomain(value[value.index(after: atIndex)...])
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
