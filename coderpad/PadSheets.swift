//
//  PadSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - New Pad sheet

struct NewPadSheet: View {
    let client: CoderPadClient
    /// A question to pre-select when the sheet opens (e.g. the widget's New Pad
    /// button seeded from a favourite). The matching title/language are filled in
    /// once the questions list loads.
    var initialQuestionID: Int?
    let onCreated: (Pad) -> Void
    let onCancel: () -> Void

    init(client: CoderPadClient, initialQuestionID: Int? = nil,
         onCreated: @escaping (Pad) -> Void, onCancel: @escaping () -> Void) {
        self.client = client
        self.initialQuestionID = initialQuestionID
        self.onCreated = onCreated
        self.onCancel = onCancel
        _selectedQuestionID = State(initialValue: initialQuestionID)
    }

    @Environment(\.orgDirectory) private var directory
    @State private var title = ""
    @State private var titleEdited = false
    @State private var titleAutofilledFromQuestionID: Int?
    @State private var language = "python3"
    /// Set once the user picks a language themselves, so a late-arriving org
    /// default doesn't overwrite their choice.
    @State private var languageEdited = false
    @State private var languageAutofilledFromQuestionID: Int?
    @State private var ownerEmail = ""
    @State private var isPrivate = false
    @State private var executionEnabled = true
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var questions: [Question] = []
    @State private var selectedQuestionID: Int?
    @State private var teams: [PadTeam] = []
    @State private var selectedTeamID: String?
    @State private var users: [OrganizationUser] = []
    /// Whether the fresh question / organization loads failed, so the sheet can say
    /// the Question, Owner, and Team choices may be incomplete instead of presenting
    /// failed data as authoritative emptiness (#863).
    @State private var questionsLoadFailed = false
    @State private var organizationLoadFailed = false

    var body: some View {
        sheetContent
            .interactiveDismissDisabled(isSubmitting)
            .task { await loadQuestions() }
            .task { await loadOrganization() }
            .task { applyOrgDefaultLanguage() }
            .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(iOS)
            NavigationStack {
                formContent
                    .padding()
                    .navigationTitle("New Pad")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { sheetToolbar }
            }
            // iPad sizes to a resizable detent and shows a drag indicator so the form
            // reads as dismissible (#610).
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
            VStack(alignment: .leading, spacing: Spacing.sheetGap) {
                Text("New Pad").font(.title3.bold())
                formContent
                actionButtons
            }
            .padding()
            .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sheetGap) {
            Form {
                TextField("Title", text: titleBinding, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

                LabeledContent("Question") {
                    SearchableQuestionPicker(selection: $selectedQuestionID, questions: questions)
                        .disabled(questions.isEmpty)
                }

                Section {
                    Picker("Language", selection: languageSelection) {
                        ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                            Text($0.coderPadLanguageDisplayName).tag($0)
                        }
                        if !CoderPadLanguages.pickerOptions.contains(language) {
                            Text(language.coderPadLanguageDisplayName).tag(language)
                        }
                    }
                } footer: {
                    Text("""
                    Need a project environment like React, Django, or Rails? \
                    [Create it on coderpad.io](\(CoderPadLanguages.projectEnvironmentsURL.absoluteString))
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                LabeledContent("Owner") {
                    SearchableOwnerPicker(ownerEmail: $ownerEmail,
                                          users: users,
                                          keyOwnerEmail: AccountsStore.shared.currentAccount?.userEmail)
                }

                if !teams.isEmpty {
                    Picker("Team", selection: $selectedTeamID) {
                        Text("Default").tag(String?.none)
                        Divider()
                        ForEach(teams, id: \.id) { team in
                            Text(team.name).tag(String?.some(team.id))
                        }
                    }
                }

                Toggle("Private", isOn: $isPrivate)
                Toggle("Execution enabled", isOn: $executionEnabled)
            }
            .formStyle(.grouped)
            .onChange(of: selectedQuestionID) { _, _ in fillFromSelectedQuestion() }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            // A prerequisite load failed: say so (with retry) rather than letting the
            // disabled Question picker and missing Team/Owner options read as a
            // genuinely empty question bank or organization (#863).
            if questionsLoadFailed || organizationLoadFailed {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(loadFailureMessage, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button("Retry") {
                        Task {
                            await loadQuestions()
                            await loadOrganization()
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var loadFailureMessage: String {
        switch (questionsLoadFailed, organizationLoadFailed) {
        case (true, true):
            String(localized: """
            Questions and organization details couldn't be loaded, so the Question, Owner, and Team \
            choices may be incomplete.
            """)
        case (true, false):
            String(localized: "Questions couldn't be loaded, so the Question choices may be incomplete.")
        default:
            String(localized: "Organization details couldn't be loaded, so the Owner and Team choices may be incomplete.")
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isSubmitting)
            createButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
            createButton
        }
    }

    private var createButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if isSubmitting {
                ProgressView().controlSize(.small)
            } else {
                Text("Create")
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSubmitting)
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    private var languageSelection: Binding<String> {
        Binding(get: { language }, set: {
            language = $0
            languageEdited = true
            languageAutofilledFromQuestionID = nil
        })
    }

    private var titleBinding: Binding<String> {
        Binding(get: { title }, set: {
            title = $0
            titleEdited = true
            titleAutofilledFromQuestionID = nil
        })
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    private func applyOrgDefaultLanguage() {
        guard !languageEdited,
              languageAutofilledFromQuestionID == nil,
              let def = directory.defaultLanguage,
              CoderPadLanguages.canCreatePad(with: def)
        else { return }

        language = def
    }

    private func resetQuestionAutofilledLanguage() {
        languageAutofilledFromQuestionID = nil
        if let def = directory.defaultLanguage,
           CoderPadLanguages.canCreatePad(with: def) {
            language = def
        } else {
            language = "python3"
        }
    }

    private func loadQuestions() async {
        if questions.isEmpty, let id = AccountsStore.shared.currentAccountID {
            questions = QuestionsCacheStore.shared.get(id)
            fillFromSelectedQuestion()
        }
        guard !client.apiKey.isEmpty else { return }

        do {
            let fresh = try await client.listQuestions()
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
            questionsLoadFailed = true
        }
    }

    /// Fills the title and language from the selected question, once it's available
    /// in the loaded list. Used both when the user picks a question and when the
    /// sheet opens pre-seeded with one (where the picker's `onChange` doesn't fire).
    /// Doesn't clobber a title the user already typed or a language they chose.
    private func fillFromSelectedQuestion() {
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
    private func loadOrganization() async {
        guard !client.apiKey.isEmpty else { return }

        do {
            let org = try await OrganizationCacheStore.shared.organization(via: client)
            organizationLoadFailed = false
            teams = org.teams
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        } catch {
            organizationLoadFailed = true
        }
    }

    private func submit() async {
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
