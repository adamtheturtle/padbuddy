//
//  InterviewTemplatesView.swift
//  coderpad
//
//  The UI for interview templates (#525): a management sheet to add, edit, and delete
//  templates, and a reusable editor sheet for a single template. Both scope to the
//  current account. The editor reuses `SearchableQuestionPicker` and the language picker
//  from the New Pad sheet so a template is built from the same primitives a pad is.
//

import SwiftUI

/// Lists the current account's templates with add / edit / delete, and a one-tap "Use"
/// that creates and opens a pad. Presented from the Pad menu's "Manage Templates…".
struct ManageTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = InterviewTemplatesStore.shared
    @State private var accounts = AccountsStore.shared

    /// The template being edited, or a fresh blank one when adding; drives the editor
    /// sheet. `Identifiable` via the template's own id.
    @State private var editing: EditingTemplate?

    private var account: Account? {
        accounts.currentAccount
    }

    private var templates: [InterviewTemplate] {
        store.templates(account: account?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Interview Templates").font(.title3.bold())
                Spacer()
                Button {
                    editing = EditingTemplate(template: nil)
                } label: {
                    Label("Add Template", systemImage: "plus")
                }
                .disabled(account == nil)
            }

            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No templates yet", systemImage: "doc.badge.plus")
                } description: {
                    Text("Save a favorite question and language as a template to start an "
                        + "interview in one step.")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(templates) { template in
                        templateRow(template)
                    }
                }
                .frame(minHeight: 240)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .sheet(item: $editing) { editingTemplate in
            if let account {
                TemplateEditorSheet(
                    account: account,
                    template: editingTemplate.template,
                    onSave: { saved in
                        if editingTemplate.template == nil {
                            store.add(saved, account: account.id)
                        } else {
                            store.update(saved, account: account.id)
                        }
                        editing = nil
                    },
                    onCancel: { editing = nil }
                )
            }
        }
    }

    private func templateRow(_ template: InterviewTemplate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline)
                Text("\(template.questionTitle) · \(template.language.languageDisplayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Use") {
                if let account { InterviewTemplateRunner.createAndOpen(template, account: account) }
                dismiss()
            }
            Menu {
                Button("Edit…") { editing = EditingTemplate(template: template) }
                Button("Delete", role: .destructive) {
                    if let account { store.remove(id: template.id, account: account.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityHidden(true)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Template actions")
        }
        .padding(.vertical, 4)
    }
}

/// Wraps a template (or `nil` for a new one) so it can drive a `.sheet(item:)`.
private struct EditingTemplate: Identifiable {
    let template: InterviewTemplate?
    let id = UUID()
}

/// Adds or edits one template. Builds the same way a pad is created — a question and a
/// language — plus a name and an optional fixed pad title. Reusable: opened blank from
/// "Add Template", pre-filled when editing, or seeded from a focused question by the
/// "Save Question as Template…" command.
struct TemplateEditorSheet: View {
    let account: Account
    /// The template being edited, or nil when creating a new one.
    let template: InterviewTemplate?
    let onSave: (InterviewTemplate) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var selectedQuestionID: Int?
    @State private var language: String
    @State private var customTitle: String
    @State private var nameEdited: Bool
    @State private var questions: [Question] = []

    init(
        account: Account,
        template: InterviewTemplate? = nil,
        seedQuestionID: Int? = nil,
        seedName: String = "",
        seedLanguage: String = "python3",
        onSave: @escaping (InterviewTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.account = account
        self.template = template
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: template?.name ?? seedName)
        _selectedQuestionID = State(initialValue: template?.questionID ?? seedQuestionID)
        _language = State(initialValue: template?.language ?? seedLanguage)
        _customTitle = State(initialValue: template?.titlePattern ?? "")
        // A name supplied up front (editing, or a seeded one) shouldn't be overwritten
        // when the question auto-fills it.
        _nameEdited = State(initialValue: !(template?.name ?? seedName).isEmpty)
    }

    private var canSave: Bool {
        selectedQuestionID != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(template == nil ? "New Template" : "Edit Template").font(.title3.bold())

            Form {
                TextField("Name", text: nameBinding,
                          prompt: Text("e.g. \"Backend phone screen\""))

                LabeledContent("Question") {
                    SearchableQuestionPicker(selection: $selectedQuestionID, questions: questions)
                        .disabled(questions.isEmpty)
                }

                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                        Text($0.languageDisplayName).tag($0)
                    }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }

                Section {
                    TextField("Pad title", text: $customTitle,
                              prompt: Text("Optional, defaults to the question's title"))
                } footer: {
                    Text("Used as the title of each pad created from this template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .onChange(of: selectedQuestionID) { _, _ in fillFromSelectedQuestion() }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 340)
        .task { await loadQuestions() }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0; nameEdited = true })
    }

    private func loadQuestions() async {
        questions = QuestionsCacheStore.shared.get(account.id)
        fillFromSelectedQuestion()
        let client = account.makeClient()
        guard !client.apiKey.isEmpty else { return }

        if let fresh = try? await client.listQuestions() {
            questions = fresh.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            fillFromSelectedQuestion()
        }
    }

    /// Fills the name (and language, for a brand-new template) from the chosen question
    /// once it's available, without clobbering a name the user typed.
    private func fillFromSelectedQuestion() {
        guard let id = selectedQuestionID,
              let question = questions.first(where: { $0.id == id }) else { return }

        if !nameEdited { name = question.displayTitle }
        if template == nil, let lang = question.language, !lang.isEmpty,
           language == "python3" {
            language = lang
        }
    }

    private func save() {
        guard let questionID = selectedQuestionID else { return }

        let questionTitle = questions.first(where: { $0.id == questionID })?.displayTitle
            ?? template?.questionTitle ?? ""
        let trimmedTitle = customTitle.trimmingCharacters(in: .whitespaces)
        let saved = InterviewTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            questionID: questionID,
            questionTitle: questionTitle,
            language: language,
            titlePattern: trimmedTitle.isEmpty ? nil : trimmedTitle,
            id: template?.id ?? UUID()
        )
        onSave(saved)
    }
}
