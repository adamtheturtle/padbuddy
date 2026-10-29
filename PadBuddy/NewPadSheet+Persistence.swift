//
//  NewPadSheet+Persistence.swift
//  coderpad
//

import SwiftUI

extension NewPadSheet {
    @ViewBuilder var duplicateSettingsPicker: some View {
        if !recentPads.isEmpty {
            Picker("Copy settings from", selection: duplicateSourceSelection) {
                Text("None").tag(String?.none)
                Divider()
                ForEach(recentPads) { pad in
                    Text(pad.title.isEmpty ? pad.id : pad.title).tag(Optional(pad.id))
                }
            }
        }
    }

    private var duplicateSourceSelection: Binding<String?> {
        Binding(
            get: { nil },
            set: { id in applyRecentPad(id: id) }
        )
    }

    var createButton: some View {
        let validationMessage = submissionValidationMessage
        return Button {
            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView().controlSize(.small)
            } else {
                Text("Create")
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isReadOnly || isSubmitting || isLoadingPrerequisites || validationMessage != nil)
        .help(createButtonHelp(validationMessage: validationMessage))
    }

    private func createButtonHelp(validationMessage: String?) -> Text {
        if isLoadingPrerequisites {
            return Text("Waiting for the question and organization details to finish loading.")
        }
        if let validationMessage {
            return Text(validationMessage)
        }
        return Text("Create the pad.")
    }

    var recentPads: [Pad] {
        guard let account = draftAccountID else { return [] }

        return PadsCacheStore.shared.recent(account)
    }

    var draftAccountID: UUID? {
        targetAccountID ?? AccountsStore.shared.account(matching: client)?.id
    }

    var persistedCreationDraft: PadCreationDraft {
        PadCreationDraft(
            title: title, language: language, ownerEmail: ownerEmail,
            isPrivate: isPrivate, executionEnabled: executionEnabled,
            questionID: selectedQuestionID, teamID: selectedTeamID, access: accessDraft
        )
    }

    func restoreCreationDraft() {
        guard let account = draftAccountID, case let .value(stored) = CreationDraftStore.load(
            PadCreationDraft.self, kind: "pad", account: account
        ) else { return }

        let draft = Self.normalizedRestoredDraft(stored)
        title = draft.title
        titleEdited = !draft.title.isEmpty
        language = draft.language
        languageEdited = true
        ownerEmail = draft.ownerEmail
        isPrivate = draft.isPrivate
        executionEnabled = draft.executionEnabled
        accessDraft = draft.access ?? PadAccessDraft()
        if initialQuestionID == nil {
            selectedQuestionID = draft.questionID
        }
        selectedTeamID = draft.teamID
    }

    /// Restore bounded editor values before the authoritative prerequisite loads
    /// reconcile the question and team selections with the current account.
    static func normalizedRestoredDraft(_ stored: PadCreationDraft) -> PadCreationDraft {
        var draft = stored
        draft.title = String(stored.title.prefix(255))
        draft.ownerEmail = String(stored.ownerEmail.prefix(254))
        draft.language = CoderPadLanguages.pickerOptions.contains(stored.language) ? stored.language : "python3"
        draft.questionID = stored.questionID.flatMap { $0 > 0 ? $0 : nil }
        draft.teamID = stored.teamID.flatMap { !$0.isEmpty && $0.utf8.count <= 256 ? $0 : nil }
        if var access = stored.access {
            access.emails = String(access.emails.prefix(25500))
            access.timeLimit = String(access.timeLimit.prefix(10))
            draft.access = access
        }
        return draft
    }

    func persistCreationDraft(_ draft: PadCreationDraft) {
        guard let account = draftAccountID else { return }

        if draft.isMeaningful {
            CreationDraftStore.save(draft, kind: "pad", account: account)
        } else {
            CreationDraftStore.clear(kind: "pad", account: account)
        }
    }

    func clearCreationDraft() {
        guard let account = draftAccountID else { return }

        CreationDraftStore.clear(kind: "pad", account: account)
    }

    func cancelDraft() {
        clearCreationDraft()
        onCancel()
    }

    func applyRecentPad(id: String?) {
        guard let id, let pad = recentPads.first(where: { $0.id == id }) else { return }

        language = pad.language ?? language
        languageEdited = true
        ownerEmail = pad.ownerEmail
        isPrivate = pad.isPrivate ?? false
        executionEnabled = pad.executionEnabled ?? true
        accessDraft.restricted = pad.restrictInterviewerAccess.map { $0 ? .enabled : .disabled } ?? .inherited
        accessDraft.replaceEmails = pad.allowedInterviewerEmails != nil
        accessDraft.emails = pad.allowedInterviewerEmails?.joined(separator: ", ") ?? ""
        selectedQuestionID = pad.questionIDs.first
        selectedTeamID = pad.team?.id
        let sourceTitle = pad.title.isEmpty ? pad.id : pad.title
        staleSelectionNotice = String(localized: "Copied settings from \(sourceTitle).")
    }
}
