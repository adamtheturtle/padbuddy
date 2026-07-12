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
    @State private var language = "python3"
    /// Set once the user picks a language themselves, so a late-arriving org
    /// default doesn't overwrite their choice.
    @State private var languageEdited = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sheetGap) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

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

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
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
        }
        .padding()
        // macOS sizes the sheet with a fixed frame; iPad sizes to a resizable detent and
        // shows a drag indicator so the form reads as dismissible (#610).
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 360)
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
            .task { await loadQuestions() }
            .task { await loadOrganization() }
            .task { applyOrgDefaultLanguage() }
            .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    private var languageSelection: Binding<String> {
        Binding(get: { language }, set: { language = $0; languageEdited = true })
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    private func applyOrgDefaultLanguage() {
        guard !languageEdited,
              let def = directory.defaultLanguage,
              CoderPadLanguages.canCreatePad(with: def)
        else { return }

        language = def
    }

    private func loadQuestions() async {
        if questions.isEmpty, let id = AccountsStore.shared.currentAccountID {
            questions = QuestionsCacheStore.shared.get(id)
            fillFromSelectedQuestion()
        }
        guard !client.apiKey.isEmpty else { return }

        if let fresh = try? await client.listQuestions() {
            questions = fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            fillFromSelectedQuestion()
        }
    }

    /// Fills the title and language from the selected question, once it's available
    /// in the loaded list. Used both when the user picks a question and when the
    /// sheet opens pre-seeded with one (where the picker's `onChange` doesn't fire).
    /// Doesn't clobber a title the user already typed or a language they chose.
    private func fillFromSelectedQuestion() {
        guard let id = selectedQuestionID,
              let question = questions.first(where: { $0.id == id }) else { return }

        if title.isEmpty { title = question.title }
        if !languageEdited,
           let lang = question.language,
           CoderPadLanguages.canCreatePad(with: lang) {
            language = lang
            // Treat the question's language as a deliberate choice so a late-arriving
            // org default (applied from `.task`/`.onChange`) can't clobber it.
            languageEdited = true
        }
    }

    /// One `organization()` call backs both the Team picker and the searchable
    /// Owner picker, so adding owner selection costs no extra network round-trip.
    private func loadOrganization() async {
        guard !client.apiKey.isEmpty else { return }

        if let org = try? await OrganizationCacheStore.shared.organization(via: client) {
            teams = org.teams
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = PadCreate(
            title: title.isEmpty ? nil : title,
            language: language,
            ownerEmail: ownerEmail.isEmpty ? nil : ownerEmail,
            contents: nil,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled,
            questionID: selectedQuestionID,
            teamID: selectedTeamID
        )
        do {
            let pad = try await client.createPad(body)
            onCreated(pad)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
