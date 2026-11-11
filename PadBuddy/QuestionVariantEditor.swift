import SwiftUI

struct QuestionVariantEditor: View {
    let client: CoderPadClient
    let questionID: Int
    @State var draft: QuestionVariantDraft
    let onSaved: (QuestionVariant) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var isSaving = false
    @State private var isActive = false
    @State private var error: String?

    var body: some View {
        sheetContent
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .onAppear { isActive = true }
            .onDisappear { isActive = false }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                Text(editorTitle).font(.title2.weight(.semibold))
                editorForm
                HStack {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                    Spacer()
                    saveButton.keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(minWidth: 540, minHeight: 500)
        #else
            NavigationStack {
                editorForm
                    .navigationTitle(editorTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }.disabled(isSaving)
                        }
                        ToolbarItem(placement: .confirmationAction) { saveButton }
                    }
            }
        #endif
    }

    private var saveButton: some View {
        Button("Save") { Task { await save() } }
            .disabled(isSaving || isReadOnly || !draft.canSave)
    }

    private var editorForm: some View {
        Form {
            Section("Environment") {
                TextField("Language or project", text: $draft.language)
                Text("Use a language such as ruby or a project template such as react.")
                    .font(.caption).foregroundStyle(.secondary)
                if draft.variantID != nil {
                    Text("""
                    Changing the environment clears starter code unless you supply replacement code or files.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            starterCodeSection
            if draft.hasUnavailableOriginalFiles {
                Text("""
                Binary or unavailable files cannot be preserved by a text replacement. Keep the current environment \
                and code to edit the solution. Replace the project in CoderPad to change these files.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            if draft.codeSource == .projectFiles {
                filesSection
            }
            Section("Reference Solution") {
                TextEditor(text: $draft.solution).font(.body.monospaced()).frame(minHeight: 100)
                    .accessibilityLabel("Reference Solution")
            }
            if let error {
                Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private var editorTitle: String {
        draft.variantID == nil ? String(localized: "Add Variant") : String(localized: "Edit Variant")
    }

    private var fileGuidance: String {
        if draft.variantID == nil {
            return String(localized: """
            Files overlay the project template. Mark a template file for deletion to remove it.
            """)
        }
        return String(localized: """
        These files replace the variant’s files. Remove all entries to restore the template’s files.
        """)
    }

    private var starterCodeSection: some View {
        Section("Starter Code") {
            Picker("Starter Code", selection: $draft.codeSource) {
                Text(draft.variantID == nil
                    ? String(localized: "Use Environment Defaults") : String(localized: "Keep Current Code"))
                    .tag(QuestionVariantDraft.CodeSource.preserve)
                Text("Use Language Default").tag(QuestionVariantDraft.CodeSource.languageDefault)
                Text("Single File").tag(QuestionVariantDraft.CodeSource.singleFile)
                Text("Project Files").tag(QuestionVariantDraft.CodeSource.projectFiles)
            }
            if draft.codeSource == .singleFile {
                TextEditor(text: $draft.contents).font(.body.monospaced()).frame(minHeight: 150)
                    .accessibilityLabel("Starter Code")
                Text("An empty editor saves a blank starter file.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filesSection: some View {
        Section("Project Files") {
            Text(fileGuidance).font(.caption).foregroundStyle(.secondary)
            if draft.isProjectTemplate {
                Button("Restore Template Files") { draft.files = [] }
            }
            ForEach($draft.files) { $file in
                fileEditor(file: $file)
            }
            Button("Add File") { draft.files.append(QuestionVariantFileDraft()) }
                .disabled(draft.files.count >= QuestionStarterFileDraft.maximumCount)
            if draft.hasInvalidFiles {
                Text("Every file needs a unique, valid path. The .cpad file cannot be deleted.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func fileEditor(file: Binding<QuestionVariantFileDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("File path", text: file.file.path)
                Button(role: .destructive) {
                    draft.files.removeAll { $0.id == file.wrappedValue.id }
                } label: {
                    Label("Remove File", systemImage: "minus.circle")
                }
                .labelStyle(.iconOnly)
            }
            Toggle("Hidden", isOn: file.hidden)
            Toggle("Delete Template File", isOn: file.deleted)
                .disabled(file.wrappedValue.file.canonicalPath == ".cpad")
            if file.wrappedValue.contentsUnavailable {
                Text(file.wrappedValue.binary == true ? "Binary file preview unavailable" : "File contents unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !file.wrappedValue.deleted {
                TextEditor(text: file.file.contents).font(.body.monospaced()).frame(minHeight: 100)
                    .accessibilityLabel("File Contents")
            }
        }
    }

    private func save() async {
        guard !isReadOnly, !isSaving, draft.canSave else { return }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved: QuestionVariant = if let id = draft.variantID {
                try await client.updateQuestionVariant(questionID: questionID, id: id, draft.mutation)
            } else {
                try await client.createQuestionVariant(questionID: questionID, draft.mutation)
            }
            guard isActive else { return }

            onSaved(saved)
            dismiss()
        } catch {
            if isActive {
                self.error = error.localizedDescription
            }
        }
    }
}
