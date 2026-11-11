//
//  NewPadSheet+Logic+Creation.swift
//  coderpad
//

import Foundation

extension NewPadSheet {
    struct CreateDraft {
        var title: String?
        var language: String?
        var ownerEmail: String?
        var contents: String?
        var notes: String?
        var isPrivate: Bool?
        var executionEnabled: Bool?
        var questionID: Int?
        var teamID: String?
        var access: PadAccessDraft?
    }

    static func normalizedCreateBody(_ draft: CreateDraft) -> PadCreate {
        let body = PadCreate(
            title: trimmedOrNil(draft.title),
            language: supportedLanguageOrNil(draft.language),
            ownerEmail: trimmedOrNil(draft.ownerEmail),
            contents: draft.contents,
            notes: draft.notes,
            isPrivate: draft.isPrivate,
            executionEnabled: draft.executionEnabled,
            questionID: draft.questionID,
            teamID: draft.teamID
        )
        return draft.access?.applying(to: body) ?? body
    }

    static func createValidationMessage(
        title: String?, ownerEmail: String?,
        questionsLoadFailed: Bool = false, organizationLoadFailed: Bool = false,
        questionID: Int? = nil, teamID: String? = nil
    ) -> String? {
        if let title = trimmedOrNil(title), title.count > 255 {
            return String(localized: "Title must be 255 characters or fewer.")
        }
        let owner = trimmedOrNil(ownerEmail)
        if let owner, !isValidEmail(owner) {
            return String(localized: "Enter a valid owner email address, or clear the Owner field.")
        }
        if questionsLoadFailed, questionID != nil {
            return String(localized: "Retry loading questions or clear the Question before creating the pad.")
        }
        if organizationLoadFailed, owner != nil || teamID != nil {
            return String(localized: """
            Retry loading organization details or clear the Owner and Team before creating the pad.
            """)
        }

        return nil
    }

    private static func isValidEmail(_ value: String) -> Bool {
        guard value.count <= 254, value.unicodeScalars.allSatisfy(\.isASCII),
              !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
        else { return false }

        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, local.count <= 64, local.first != ".", local.last != ".",
              !local.contains(".."), domain.contains(".")
        else { return false }

        let localAllowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~")
        guard local.unicodeScalars.allSatisfy(localAllowed.contains) else { return false }

        return domain.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.unicodeScalars.allSatisfy {
                    CharacterSet.alphanumerics.contains($0) || $0 == "-"
                }
        }
    }

    /// The language to send, or `nil` to let the account default apply.
    ///
    /// Sends a canonical picker identifier, including supported project templates.
    private static func supportedLanguageOrNil(_ value: String?) -> String? {
        guard CoderPadLanguages.canCreatePad(with: value), let value else { return nil }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Trims a free-text field to what the API can store, or `nil` when nothing is
    /// left.
    ///
    /// Interior control characters are folded to a single space as well as
    /// surrounding whitespace being trimmed. Trimming alone let a newline pasted
    /// into the middle of a title through, making a label that renders broken
    /// everywhere it appears, and let one inside an owner address through, making a
    /// request that can never match a member (#2639). Folding rather than deleting
    /// keeps the words either side of the break apart.
    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value
            .components(separatedBy: .controlCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
