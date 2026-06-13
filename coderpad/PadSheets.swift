//
//  PadSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - New Pad sheet

struct NewPadSheet: View {
    let client: CoderPadClient
    let onCreated: (Pad) -> Void
    let onCancel: () -> Void

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
        VStack(alignment: .leading, spacing: 14) {
            Text("New Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))

                LabeledContent("Question") {
                    SearchableQuestionPicker(selection: $selectedQuestionID, questions: questions)
                        .disabled(questions.isEmpty)
                }

                Picker("Language", selection: languageSelection) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
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
            .onChange(of: selectedQuestionID) { _, newValue in
                guard let id = newValue, let question = questions.first(where: { $0.id == id }) else { return }
                if title.isEmpty { title = question.title }
                if let lang = question.language, !lang.isEmpty { language = lang }
            }

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
        .frame(minWidth: 460, minHeight: 360)
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
        guard !languageEdited, let def = directory.defaultLanguage, !def.isEmpty else { return }
        language = def
    }

    private func loadQuestions() async {
        if questions.isEmpty, let id = AccountsStore.shared.currentAccountID {
            questions = QuestionsCacheStore.shared.get(id)
        }
        guard !client.apiKey.isEmpty else { return }
        if let fresh = try? await client.listQuestions() {
            questions = fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        }
    }

    /// One `organization()` call backs both the Team picker and the searchable
    /// Owner picker, so adding owner selection costs no extra network round-trip.
    private func loadOrganization() async {
        guard !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
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

// MARK: - Edit Pad sheet

struct EditPadSheet: View {
    let client: CoderPadClient
    let original: Pad
    let onSaved: (Pad) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var language: String
    @State private var ownerEmail: String
    @State private var isPrivate: Bool
    @State private var executionEnabled: Bool
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var users: [OrganizationUser] = []

    init(client: CoderPadClient,
         original: Pad,
         onSaved: @escaping (Pad) -> Void,
         onCancel: @escaping () -> Void) {
        self.client = client
        self.original = original
        self.onSaved = onSaved
        self.onCancel = onCancel
        _title = State(initialValue: original.title)
        _language = State(initialValue: original.language ?? "python3")
        _ownerEmail = State(initialValue: original.ownerEmail)
        _isPrivate = State(initialValue: original.isPrivate ?? false)
        _executionEnabled = State(initialValue: original.executionEnabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Pad").font(.title3.bold())

            Form {
                TextField("Title", text: $title)
                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }
                LabeledContent("Owner") {
                    SearchableOwnerPicker(ownerEmail: $ownerEmail,
                                          users: users,
                                          keyOwnerEmail: AccountsStore.shared.currentAccount?.userEmail)
                }
                Toggle("Private", isOn: $isPrivate)
                Toggle("Execution enabled", isOn: $executionEnabled)
            }
            .formStyle(.grouped)

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
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 360)
        .task { await loadOrganizationUsers() }
    }

    /// Loads org members so the owner field offers a searchable, named picker.
    /// Falls back silently to free-text entry when the list is empty or unavailable.
    private func loadOrganizationUsers() async {
        guard !client.apiKey.isEmpty else { return }
        if let org = try? await client.organization() {
            users = org.users.sorted {
                ($0.name ?? $0.email).localizedCaseInsensitiveCompare($1.name ?? $1.email) == .orderedAscending
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = PadUpdate(
            id: original.id,
            title: title,
            language: language,
            ownerEmail: ownerEmail.isEmpty ? nil : ownerEmail,
            notes: nil,
            isPrivate: isPrivate,
            executionEnabled: executionEnabled
        )
        do {
            let updated = try await client.updatePad(body)
            onSaved(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
