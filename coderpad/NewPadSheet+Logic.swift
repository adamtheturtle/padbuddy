//
//  NewPadSheet+Logic.swift
//  coderpad
//
//  The loading and submission half of `NewPadSheet`, split from PadSheets.swift
//  to keep both files under the file-length limit.
//

import Foundation
import SwiftUI

// MARK: - Loading and submission

extension NewPadSheet {
    var isLoadingPrerequisites: Bool {
        questionsLoading || organizationLoading
    }

    var targetAccountName: String {
        let id = targetAccountID ?? AccountsStore.shared.currentAccountID
        return id.flatMap { target in
            AccountsStore.shared.accounts.first(where: { $0.id == target })?.name
        } ?? String(localized: "the selected account")
    }

    var loadFailureMessage: String {
        let incomplete = switch (questionsLoadFailed, organizationLoadFailed) {
        case (true, true):
            String(localized: """
            Questions and organization details could not be loaded, so the Question, Owner, and Team \
            choices may be incomplete.
            """)

        case (true, false):
            String(localized: "Questions could not be loaded, so the Question choices may be incomplete.")

        default:
            String(localized: """
            Organization details could not be loaded, so the Owner and Team choices may be incomplete.
            """)
        }
        guard let unverified = unverifiedSelectionsMessage else { return incomplete }

        return "\(incomplete) \(unverified)"
    }

    /// Names the choices that the failed loads left unverified, or `nil` when
    /// nothing is currently selected that a load would have validated.
    ///
    /// Saying only that the *choices* may be incomplete was ambiguous: creation
    /// stays enabled, so the user couldn't tell whether the value already in each
    /// picker was known good or a cached leftover that the API will reject
    /// (#2637). Listing them makes the risk of pressing Create concrete.
    private var unverifiedSelectionsMessage: String? {
        var fields: [String] = []
        if questionsLoadFailed, selectedQuestionID != nil {
            fields.append(String(localized: "Question",
                                 comment: "New Pad field name in an unverified-selection warning"))
        }
        if organizationLoadFailed {
            if !ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields.append(String(localized: "Owner",
                                     comment: "New Pad field name in an unverified-selection warning"))
            }
            if selectedTeamID != nil {
                fields.append(String(localized: "Team",
                                     comment: "New Pad field name in an unverified-selection warning"))
            }
        }
        guard !fields.isEmpty else { return nil }

        let list = ListFormatter.localizedString(byJoining: fields)
        return String(localized: "The current \(list) selection could not be verified and may fail.",
                      comment: "Warning naming the New Pad selections a failed load left unverified")
    }

    func loadQuestions() async {
        guard loadLifetime.isActive else { return }

        let lifetimeRevision = loadLifetime.revision
        if questions.isEmpty, let id = targetAccountID ?? AccountsStore.shared.currentAccountID {
            setQuestions(QuestionsCacheStore.shared.get(id))
            fillFromSelectedQuestion()
        }
        guard !client.apiKey.isEmpty else { return }

        questionsLoadGeneration += 1
        let generation = questionsLoadGeneration
        questionsLoading = true
        defer { if generation == questionsLoadGeneration { questionsLoading = false } }
        do {
            let fresh = try await client.listQuestions()
            // A newer load started while this one was in flight: its answer is the
            // current truth, so drop this stale one rather than winding the list
            // and the selection back to an older snapshot (#2636).
            guard generation == questionsLoadGeneration,
                  loadLifetime.isCurrent(lifetimeRevision, taskIsCancelled: Task.isCancelled) else { return }

            questionsLoadFailed = false
            setQuestions(fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) })
            // The authoritative list just replaced the cached one: a selection that no
            // longer resolves must be cleared, not submitted invisibly - the picker
            // would show "None" while the create request still carried the id (#864).
            // Clearing it is announced, because a user who picked from the cached list
            // while this request was in flight would otherwise watch their choice
            // vanish for no stated reason (#2634).
            if let id = selectedQuestionID, questionsByID[id] == nil {
                selectedQuestionID = nil
                staleSelectionNotice = String(localized: """
                The question you picked is no longer in this account's question bank, so it has been cleared.
                """)
            }
            fillFromSelectedQuestion()
        } catch {
            guard generation == questionsLoadGeneration,
                  loadLifetime.isCurrent(lifetimeRevision, taskIsCancelled: Task.isCancelled) else { return }

            questionsLoadFailed = true
        }
    }

    /// Replaces the loaded questions and their id index together, so the two can't
    /// drift apart.
    func setQuestions(_ loaded: [Question]) {
        questions = loaded
        questionsByID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Fills the title and language from the selected question, once it's available
    /// in the loaded list. Used both when the user picks a question and when the
    /// sheet opens pre-seeded with one (where the picker's `onChange` doesn't fire).
    /// Doesn't clobber a title the user already typed or a language they chose.
    func fillFromSelectedQuestion() {
        guard let id = selectedQuestionID else {
            if titleAutofilledFromQuestionID != nil {
                title = ""
                titleEdited = false
                titleAutofilledFromQuestionID = nil
            }
            if languageAutofilledFromQuestionID != nil {
                resetQuestionAutofilledLanguage()
            }
            return
        }
        guard let question = questionsByID[id] else { return }

        if !titleEdited || titleAutofilledFromQuestionID != nil {
            title = question.title
            titleEdited = false
            titleAutofilledFromQuestionID = id
        }
        if !languageEdited,
           let lang = question.language,
           CoderPadLanguages.canCreatePad(with: lang) {
            language = lang
            languageAutofilledFromQuestionID = id
        } else if !languageEdited, languageAutofilledFromQuestionID != nil {
            resetQuestionAutofilledLanguage()
        }
    }

    /// One `organization()` call backs both the Team picker and the searchable
    /// Owner picker, so adding owner selection costs no extra network round-trip.
    func loadOrganization() async {
        guard !client.apiKey.isEmpty, loadLifetime.isActive else { return }

        let lifetimeRevision = loadLifetime.revision

        organizationLoadGeneration += 1
        let generation = organizationLoadGeneration
        organizationLoading = true
        defer { if generation == organizationLoadGeneration { organizationLoading = false } }
        do {
            let org = try await OrganizationCacheStore.shared.organization(via: client)
            // Retry can overlap the opening load; only the newest response may
            // write the pickers, so an older one can't undo fresher data (#2635).
            guard generation == organizationLoadGeneration,
                  loadLifetime.isCurrent(lifetimeRevision, taskIsCancelled: Task.isCancelled) else { return }

            organizationLoadFailed = false
            if let status = OrganizationCacheStore.shared.status(via: client) {
                organizationLoadFailed = status.isStale || status.refreshError != nil
            }
            teams = org.teams
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
            validateSelectionsAgainstOrganization()
        } catch {
            guard generation == organizationLoadGeneration,
                  loadLifetime.isCurrent(lifetimeRevision, taskIsCancelled: Task.isCancelled) else { return }

            organizationLoadFailed = true
        }
    }

    func cancelPrerequisiteLoads() {
        loadLifetime.invalidate()
        questionsLoadGeneration &+= 1
        organizationLoadGeneration &+= 1
        questionsLoading = false
        organizationLoading = false
    }

    /// Re-checks the Team and Owner picks against a freshly loaded organization.
    ///
    /// Both can go stale while the sheet is open — a team is deleted, a colleague
    /// offboards — and neither was verified before, so the create request carried
    /// a value the API would reject (#2632, #2633).
    ///
    /// The two are handled differently on purpose. The Team picker offers a closed
    /// set, so an ID that has disappeared can only be wrong: reset it to Default.
    /// The Owner field is deliberately free text (see `SearchableOwnerPicker`) —
    /// orgs whose key isn't an owner return no member list at all, and assigning
    /// an unlisted address is legitimate — so an unrecognized owner is flagged,
    /// never overwritten.
    func validateSelectionsAgainstOrganization() {
        if let teamID = selectedTeamID, !teams.contains(where: { $0.id == teamID }) {
            selectedTeamID = nil
            staleSelectionNotice = String(localized: """
            The team you picked is no longer in this organization, so the pad will use the default team.
            """)
            return
        }

        let owner = ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !users.isEmpty,
              !users.contains(where: { $0.email.caseInsensitiveCompare(owner) == .orderedSame })
        else { return }

        staleSelectionNotice = String(
            localized: "\(owner) is not a member of this organization, so creating the pad may fail.",
            comment: "Warning when the chosen New Pad owner is not in the loaded organization member list"
        )
    }

    func submit() async {
        guard let validationMessage = submissionValidationMessage else {
            await performSubmit()
            return
        }

        error = validationMessage
    }

    private func performSubmit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = Self.normalizedCreateBody(Self.CreateDraft(
            title: title,
            language: language,
            ownerEmail: ownerEmail,
            contents: nil,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled,
            questionID: selectedQuestionID,
            teamID: selectedTeamID
        ))
        do {
            let context = AccountClientContext(client: client, targetAccountID: targetAccountID)
            guard let account = context.resolve(in: AccountsStore.shared.accounts) else {
                throw AccountClientContextError.accountChanged
            }

            let pad = try await account.makeClient().createPad(body)
            guard context.resolve(in: AccountsStore.shared.accounts) != nil else {
                throw AccountClientContextError.accountChanged
            }

            onCreated(pad)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

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
    }

    static func normalizedCreateBody(_ draft: CreateDraft) -> PadCreate {
        PadCreate(
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
    /// Only a code the pad-creation API actually accepts is forwarded. A question
    /// carrying a project environment (React, Rails — creatable only in the web
    /// app), or a stale or unknown code reaching a programmatic draft, otherwise
    /// produced a request the server rejects outright (#2638). The accepted code is
    /// sent in the canonical trimmed, lowercased form the gate matched on.
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
