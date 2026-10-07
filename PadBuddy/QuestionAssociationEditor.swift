import SwiftUI

struct QuestionAssociationFields: View {
    @Binding var draft: QuestionAssociationDraft

    var body: some View {
        Picker("Shared", selection: $draft.shared) {
            Text("Default / unchanged").tag(Bool?.none)
            Text("Yes").tag(Bool?.some(true))
            Text("No").tag(Bool?.some(false))
        }
        TextField("Custom database ID", text: $draft.databaseID)
        Text("An empty database ID preserves the association. Use the ID supplied by your organization.")
            .font(.caption).foregroundStyle(.secondary)
        if let message = draft.validationMessage {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}

struct QuestionAssociationEditor: View {
    let client: CoderPadClient
    let question: Question
    let isCurrent: () -> Bool
    let onSaved: (Question) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var draft = QuestionAssociationDraft()
    @State private var model = QuestionAssociationModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Question Settings") {
                    if let shared = question.shared {
                        LabeledContent("Shared") { Text(shared ? "Yes" : "No") }
                    }
                    if let database = question.customDatabase {
                        LabeledContent("Custom database ID", value: String(database.id))
                    }
                }
                Section {
                    QuestionAssociationFields(draft: $draft)
                } header: {
                    Text("Sharing and Database")
                } footer: {
                    Text("Sharing and database changes require question authoring permission.")
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .disabled(model.saving || isReadOnly)
            .navigationTitle("Sharing and Database")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if let updated = await model.save(draft, questionID: question.id, client: client,
                                                              isCurrent: { !isReadOnly && isCurrent() }) {
                                onSaved(updated)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.saving || isReadOnly || !draft.isMeaningful || draft.validationMessage != nil)
                }
            }
        }
        .interactiveDismissDisabled(model.saving)
        #if os(macOS)
            .frame(minWidth: 500, minHeight: 380)
        #endif
    }
}
