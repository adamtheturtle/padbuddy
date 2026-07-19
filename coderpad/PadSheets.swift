//
//  PadSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - New Pad sheet

struct NewPadSheet: View {
    let client: CoderPadClient
    let targetAccountID: UUID?
    let keyOwnerEmail: String?
    /// A question to pre-select when the sheet opens (e.g. the widget's New Pad
    /// button seeded from a favourite). The matching title/language are filled in
    /// once the questions list loads.
    var initialQuestionID: Int?
    let onCreated: (Pad) -> Void
    let onCancel: () -> Void

    init(client: CoderPadClient, targetAccountID: UUID? = nil, keyOwnerEmail: String? = nil,
         initialQuestionID: Int? = nil,
         onCreated: @escaping (Pad) -> Void, onCancel: @escaping () -> Void) {
        self.client = client
        self.targetAccountID = targetAccountID
        self.keyOwnerEmail = keyOwnerEmail
        self.initialQuestionID = initialQuestionID
        self.onCreated = onCreated
        self.onCancel = onCancel
        _selectedQuestionID = State(initialValue: initialQuestionID)
    }

    // The drafts below are internal rather than private because the loading and
    // submission half of this view lives in NewPadSheet+Logic.swift, split out to
    // keep both files under the file-length limit — the same shape as the other
    // split editors (e.g. AccountEditor / AccountEditor+Logic).
    @Environment(\.orgDirectory) var directory
    @State var title = ""
    @State var titleEdited = false
    @State var titleAutofilledFromQuestionID: Int?
    @State var language = "python3"
    /// Set once the user picks a language themselves, so a late-arriving org
    /// default doesn't overwrite their choice.
    @State var languageEdited = false
    @State var languageAutofilledFromQuestionID: Int?
    @State var ownerEmail = ""
    @State var isPrivate = false
    @State var executionEnabled = true
    @State var isSubmitting = false
    @State var error: String?
    @State var questions: [Question] = []
    @State var selectedQuestionID: Int?
    @State var teams: [PadTeam] = []
    @State var selectedTeamID: String?
    @State var users: [OrganizationUser] = []
    /// Whether the fresh question / organization loads failed, so the sheet can say
    /// the Question, Owner, and Team choices may be incomplete instead of presenting
    /// failed data as authoritative emptiness (#863).
    @State var questionsLoadFailed = false
    @State var organizationLoadFailed = false

    var body: some View {
        sheetContent
            .interactiveDismissDisabled(isSubmitting)
            .task { await loadQuestions() }
            .task { await loadOrganization() }
            .task { applyOrgDefaultLanguage() }
            .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
            // A new seed arriving while the sheet is mounted (another widget or
            // deep-link New Pad request) is a new user intent: apply it instead
            // of silently keeping the original question (#2630).
            .onChange(of: initialQuestionID) { _, newValue in
                guard let newValue, selectedQuestionID != newValue else { return }

                selectedQuestionID = newValue
            }
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
                                          keyOwnerEmail: keyOwnerEmail
                                              ?? AccountsStore.shared.currentAccount?.userEmail)
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

    func resetQuestionAutofilledLanguage() {
        languageAutofilledFromQuestionID = nil
        if let def = directory.defaultLanguage,
           CoderPadLanguages.canCreatePad(with: def) {
            language = def
        } else {
            language = "python3"
        }
    }
}
