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
    var loadFailureMessage: String {
        switch (questionsLoadFailed, organizationLoadFailed) {
        case (true, true):
            String(localized: """
            Questions and organization details couldn't be loaded, so the Question, Owner, and Team \
            choices may be incomplete.
            """)

        case (true, false):
            String(localized: "Questions couldn't be loaded, so the Question choices may be incomplete.")

        default:
            String(localized: """
            Organization details couldn't be loaded, so the Owner and Team choices may be incomplete.
            """)
        }
    }

    func loadQuestions() async {
        if questions.isEmpty, let id = targetAccountID ?? AccountsStore.shared.currentAccountID {
            questions = QuestionsCacheStore.shared.get(id)
            fillFromSelectedQuestion()
        }
        guard !client.apiKey.isEmpty else { return }

        questionsLoadGeneration += 1
        let generation = questionsLoadGeneration
        do {
            let fresh = try await client.listQuestions()
            // A newer load started while this one was in flight: its answer is the
            // current truth, so drop this stale one rather than winding the list
            // and the selection back to an older snapshot (#2636).
            guard generation == questionsLoadGeneration else { return }

            questionsLoadFailed = false
            questions = fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            // The authoritative list just replaced the cached one: a selection that no
            // longer resolves must be cleared, not submitted invisibly - the picker
            // would show "None" while the create request still carried the id (#864).
            if let id = selectedQuestionID, !questions.contains(where: { $0.id == id }) {
                selectedQuestionID = nil
            }
            fillFromSelectedQuestion()
        } catch {
            guard generation == questionsLoadGeneration else { return }

            questionsLoadFailed = true
        }
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
        guard let question = questions.first(where: { $0.id == id }) else { return }

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
        guard !client.apiKey.isEmpty else { return }

        organizationLoadGeneration += 1
        let generation = organizationLoadGeneration
        do {
            let org = try await OrganizationCacheStore.shared.organization(via: client)
            // Retry can overlap the opening load; only the newest response may
            // write the pickers, so an older one can't undo fresher data (#2635).
            guard generation == organizationLoadGeneration else { return }

            organizationLoadFailed = false
            teams = org.teams
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        } catch {
            guard generation == organizationLoadGeneration else { return }

            organizationLoadFailed = true
        }
    }

    func submit() async {
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
            let pad = try await client.createPad(body)
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
            language: draft.language,
            ownerEmail: trimmedOrNil(draft.ownerEmail),
            contents: draft.contents,
            notes: draft.notes,
            isPrivate: draft.isPrivate,
            executionEnabled: draft.executionEnabled,
            questionID: draft.questionID,
            teamID: draft.teamID
        )
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
