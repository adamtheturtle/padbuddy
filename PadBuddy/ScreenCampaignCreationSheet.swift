import SwiftUI

struct ScreenCampaignCreationSheet: View {
    let client: ScreenClient
    let accountID: UUID
    let onCreated: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var draft = ScreenCampaignDraft()
    @State private var model = ScreenCampaignCreationModel()
    @State private var bank = ScreenQuestionBankModel()

    private var identity: ScreenBankIdentity {
        ScreenBankIdentity(accountID: accountID, clientIdentity: client.taskIdentity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Campaign") {
                    TextField("Name", text: $draft.name)
                    TextField("Team UUID (optional)", text: $draft.teamID)
                    Text("Creating in \(accountName)").font(.caption)
                }
                questions
                ScreenCampaignSettingsFields(draft: $draft.settings)
                if let message = draft.validationMessage ?? model.error {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let id = model.createdID {
                    Text("Campaign \(id) was created.")
                    if model.contextChangedAfterCreation {
                        Text("""
                        The account changed after creation. Return to its Screen campaigns and refresh to find it.
                        """)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(model.saving || model.createdID != nil || isReadOnly)
            .navigationTitle("New Screen Campaign")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.createdID == nil ? LocalizedStringKey("Cancel") : LocalizedStringKey("Done")) {
                        dismiss()
                    }.disabled(model.saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if let id = await model.create(draft, client: client,
                                                           isCurrent: { !isReadOnly && isCurrentContext }) {
                                onCreated(id)
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.saving || model.createdID != nil || isReadOnly || draft.validationMessage != nil)
                }
            }
        }
        .interactiveDismissDisabled(model.saving)
        .task(id: identity) { await bank.reload(client: client, identity: identity, filters: ScreenQuestionFilters()) }
        #if os(macOS)
            .frame(minWidth: 620, minHeight: 650)
        #endif
    }

    private var questions: some View {
        Section("Campaign Questions") {
            ForEach($draft.questions) { $question in
                VStack(alignment: .leading, spacing: 10) {
                    if question.random != nil {
                        ScreenRandomQuestionFields(draft: Binding(
                            get: { question.random ?? ScreenRandomQuestionDraft() },
                            set: { question.random = $0 }
                        ))
                    } else {
                        Picker("Question", selection: $question.questionID) {
                            Text("Choose a question").tag(UUID?.none)
                            ForEach(bank.questions) { summary in
                                Text(verbatim: ScreenBankText.localized(summary.title) ?? summary.id.uuidString)
                                    .tag(Optional(summary.id))
                            }
                        }
                    }
                    HStack {
                        Button("Move Up", systemImage: "arrow.up") { move(question.id, by: -1) }
                        Button("Move Down", systemImage: "arrow.down") { move(question.id, by: 1) }
                        Button("Remove", systemImage: "minus.circle", role: .destructive) {
                            draft.questions.removeAll { $0.id == question.id }
                        }
                    }
                    .buttonStyle(.borderless)
                    Divider()
                }
            }
            Button("Add Fixed Question", systemImage: "plus") {
                draft.questions.append(ScreenCampaignQuestionDraft())
            }.disabled(draft.questions.count >= 200)
            Button("Add Random Question Set", systemImage: "shuffle") {
                draft.questions.append(ScreenCampaignQuestionDraft(random: ScreenRandomQuestionDraft()))
            }.disabled(draft.questions.count >= 200)
            if bank.loading {
                ProgressView("Loading Screen questions…")
            } else if let error = bank.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Retry") {
                    Task { await bank.reload(client: client, identity: identity, filters: ScreenQuestionFilters()) }
                }
            } else if bank.questions.isEmpty {
                Text("No fixed questions are available in this account.").foregroundStyle(.secondary)
            }
            if bank.nextStart != nil {
                Button("Load More Questions") { Task { await bank.loadMore(client: client, identity: identity) } }
                    .disabled(bank.loading)
            }
        }
    }

    private var accountName: String {
        AccountsStore.shared.accounts.first { $0.id == accountID }?.name ?? String(localized: "Unknown account")
    }

    private var isCurrentContext: Bool {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == accountID }),
              let current = account.makeScreenClient() else { return false }

        return current.taskIdentity == identity.clientIdentity
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let current = draft.questions.firstIndex(where: { $0.id == id }),
              draft.questions.indices.contains(current + offset) else { return }

        draft.questions.swapAt(current, current + offset)
    }
}
