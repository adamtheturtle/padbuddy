//
//  PadSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - New Pad sheet

struct NewPadLoadLifetime {
    private(set) var revision = 0
    private(set) var isActive = true

    mutating func activate() {
        guard !isActive else { return }

        revision &+= 1
        isActive = true
    }

    mutating func invalidate() {
        revision &+= 1
        isActive = false
    }

    func isCurrent(_ claim: Int, taskIsCancelled: Bool) -> Bool {
        isActive && revision == claim && !taskIsCancelled
    }
}

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
         initialQuestionID: Int? = nil, initialError: String? = nil,
         onCreated: @escaping (Pad) -> Void, onCancel: @escaping () -> Void) {
        self.client = client
        self.targetAccountID = targetAccountID
        self.keyOwnerEmail = keyOwnerEmail
        self.initialQuestionID = initialQuestionID
        self.onCreated = onCreated
        self.onCancel = onCancel
        _selectedQuestionID = State(initialValue: initialQuestionID)
        _error = State(initialValue: initialError)
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
    /// `questions` keyed by id, kept in step with it by `setQuestions`.
    ///
    /// The picker's onChange fills the title and language from the selected question,
    /// and the load clears a selection that no longer resolves — both of which
    /// scanned the whole question bank, which can be large (#2476).
    @State var questionsByID: [Int: Question] = [:]
    @State var selectedQuestionID: Int?
    @State var teams: [PadTeam] = []
    @State var selectedTeamID: String?
    @State var users: [OrganizationUser] = []
    /// Whether the fresh question / organization loads failed, so the sheet can say
    /// the Question, Owner, and Team choices may be incomplete instead of presenting
    /// failed data as authoritative emptiness (#863).
    @State var questionsLoadFailed = false
    @State var organizationLoadFailed = false
    /// Claim tickets for the newest question / organization load. The opening
    /// `.task` and Retry can overlap, and an older response finishing last must
    /// not replace a fresher list or re-clear the selection (#2635, #2636).
    @State var questionsLoadGeneration = 0
    @State var organizationLoadGeneration = 0
    @State var loadLifetime = NewPadLoadLifetime()
    /// Whether each load is still in flight. Create stays disabled until both
    /// settle, so a cached question, owner, or team can't be submitted before the
    /// authoritative data that would validate it arrives (#2631).
    @State var questionsLoading = false
    @State var organizationLoading = false
    /// Set when arriving authoritative data invalidated something the user had
    /// already chosen. The sheet says so instead of silently dropping the pick or
    /// silently sending a value the organization no longer knows (#2632–#2634).
    @State var staleSelectionNotice: String?

    var body: some View {
        sheetContent
            .interactiveDismissDisabled(isSubmitting)
            .task { await loadQuestions() }
            .task { await loadOrganization() }
            .task { restoreCreationDraft() }
            .task { applyOrgDefaultLanguage() }
            .onChange(of: persistedCreationDraft) { _, draft in persistCreationDraft(draft) }
            .onAppear { loadLifetime.activate() }
            .onDisappear { cancelPrerequisiteLoads() }
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
                Section {
                    Label("Creating in \(targetAccountName)", systemImage: "person.crop.circle")
                        .font(.callout.weight(.semibold))
                } footer: {
                    Text("Question, language availability, Owner, and Team are loaded from this account. "
                        + "Switch accounts before creating if these choices belong elsewhere.")
                        .foregroundStyle(.secondary)
                }

                TextField("Title", text: titleBinding, prompt: Text("Optional, e.g. \"Onsite: Jane Doe\""))
                duplicateSettingsPicker

                LabeledContent("Question") {
                    SearchableQuestionPicker(selection: clearingStaleNotice($selectedQuestionID),
                                             questions: questions)
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
                    SearchableOwnerPicker(ownerEmail: clearingStaleNotice($ownerEmail),
                                          users: users,
                                          keyOwnerEmail: keyOwnerEmail
                                              ?? AccountsStore.shared.currentAccount?.userEmail)
                }

                if !teams.isEmpty {
                    Picker("Team", selection: clearingStaleNotice($selectedTeamID)) {
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
                fillFromSelectedQuestion()
                guard let newValue, questionsByID[newValue] == nil else { return }

                Task { await loadSelectedQuestion(newValue) }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if let validationMessage = submissionValidationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            }

            // A choice the user had already made stopped resolving when fresher
            // data arrived. Say which one, so the reset picker isn't a silent
            // surprise at create time (#2632–#2634).
            if let staleSelectionNotice {
                Label(staleSelectionNotice, systemImage: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(.secondary)
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
            Button("Cancel", role: .cancel, action: cancelDraft)
                .disabled(isSubmitting)
            createButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: cancelDraft)
                .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
            createButton
        }
    }

    var submissionValidationMessage: String? {
        Self.createValidationMessage(
            title: title, ownerEmail: ownerEmail,
            questionsLoadFailed: questionsLoadFailed,
            organizationLoadFailed: organizationLoadFailed,
            questionID: selectedQuestionID,
            teamID: selectedTeamID
        )
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

    /// Wraps a picker's binding so the stale-selection notice is dismissed when the
    /// user acts on it. Only writes that come through the picker clear it: the
    /// loads that raise the notice write their `@State` directly, so they can't
    /// wipe the very message they just posted (#2632–#2634).
    private func clearingStaleNotice<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: {
            binding.wrappedValue = $0
            staleSelectionNotice = nil
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
