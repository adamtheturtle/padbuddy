import SwiftUI
import UniformTypeIdentifiers

struct ScreenQuestionAuthoringSheet: View {
    let client: ScreenClient
    let bankIdentity: ScreenBankIdentity
    let questionID: UUID?
    let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var model = ScreenQuestionAuthoringModel()
    @State private var importing = false
    @State private var readingArchive = false
    @State private var teamID = ""

    private var invalidTeam: Bool {
        !teamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && UUID(uuidString: teamID) == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.ready {
                    common
                    content
                    ScreenQuestionFields.included(
                        String(localized: "Evaluation"),
                        value: $model.draft.evaluation,
                        make: ScreenEvaluationInput()
                    ) { ScreenQuestionFields.fields($0)
                    }
                }
                if model.loading {
                    ProgressView("Loading question details…")
                }
                if model.uploading || readingArchive {
                    ProgressView("Uploading project archive…")
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    if !model.ready {
                        Button("Retry") { Task { await prepare() } }
                    }
                }
                if invalidTeam {
                    Text("Enter a valid team UUID or leave it empty for the default team.")
                }
                if model.contextChangedAfterSave {
                    Text("The question was saved. Return to the original account and refresh its question bank.")
                }
            }
            .formStyle(.grouped)
            .disabled(isReadOnly || model.saving || model.uploading || readingArchive || model.savedID != nil)
            .navigationTitle(questionID == nil ? "New Screen Question" : "Edit Screen Question")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.savedID == nil ? LocalizedStringKey("Cancel") : LocalizedStringKey("Done")) {
                        dismiss()
                    }
                    .disabled(model.saving || model.uploading || readingArchive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!model.ready || invalidTeam || isReadOnly || model.saving || model.uploading
                            || readingArchive || model.savedID != nil)
                }
            }
        }
        .task(id: bankIdentity) { await prepare() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gzip]) { result in
            Task { await upload(result) }
        }
        #if os(macOS)
        .frame(minWidth: 660, minHeight: 650)
        #endif
    }

    private var common: some View {
        Section("Question") {
            Picker("Question type", selection: Binding(get: { model.draft.type }, set: model.changeType)) {
                ForEach(ScreenQuestionSave.QuestionType.allCases, id: \.self) {
                    Text(verbatim: $0.rawValue).tag($0)
                }
            }.disabled(questionID != nil)
            ScreenQuestionFields.localized(String(localized: "Title"), value: $model.draft.title)
            ScreenQuestionFields.localized(String(localized: "Statement"), value: $model.draft.statement)
            ScreenQuestionFields.array(
                String(localized: "Content languages"),
                value: $model.draft.locales,
                make: "en"
            ) { TextField("Language code", text: $0) }
            ScreenQuestionFields.text(String(localized: "Domain"), value: $model.draft.domain)
            ScreenQuestionFields.text(String(localized: "Skill"), value: $model.draft.skill)
            ScreenQuestionFields.integer(
                String(localized: "Duration in seconds"),
                value: $model.draft.durationSeconds
            )
            ScreenQuestionFields.integer(String(localized: "Maximum points"), value: $model.draft.points)
            ScreenQuestionFields.enumeration(
                String(localized: "Difficulty"),
                value: $model.draft.difficulty,
                type: ScreenQuestionSave.Difficulty.self
            )
            ScreenQuestionFields.boolean(
                String(localized: "Automatically selectable"),
                value: $model.draft.automaticallySelectable
            )
            ScreenQuestionFields.text(String(localized: "Comment"), value: $model.draft.comment)
            TextField("Team UUID (optional)", text: $teamID)
            Text(
                "Unchecked fields use service defaults. Included empty lists and disabled choices are sent explicitly."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.draft.type {
        case .mcq:
            ScreenQuestionFields.included(
                String(localized: "Multiple choice"),
                value: $model.draft.mcqDetails,
                make: ScreenMCQInput()
            ) { ScreenQuestionFields.fields($0) }

        case .code:
            ScreenQuestionFields.included(
                String(localized: "Code"),
                value: $model.draft.codeDetails,
                make: ScreenCodeInput()
            ) { ScreenQuestionFields.fields($0) }

        case .text:
            ScreenQuestionFields.included(
                String(localized: "Text response"),
                value: $model.draft.textDetails,
                make: ScreenTextInput()
            ) { ScreenQuestionFields.fields($0) }

        case .video:
            ScreenQuestionFields.included(
                String(localized: "Recording"),
                value: $model.draft.videoDetails,
                make: ScreenVideoInput()
            ) { ScreenQuestionFields.fields($0) }

        case .project:
            ScreenQuestionFields.included(
                String(localized: "Project"),
                value: $model.draft.projectDetails,
                make: ScreenProjectInput()
            ) { ScreenQuestionFields.fields($0) }
            Section("Project archive") {
                if questionID == nil {
                    Button("Choose Gzip Archive…", systemImage: "square.and.arrow.up") { importing = true }
                    if model.draft.projectDetails?.temporaryFileID != nil, let filename = model.uploadFilename {
                        Text("Uploaded: \(filename)")
                    }
                    Text(
                        "Choose a tar.gz archive up to 50 MiB. The archive is uploaded once without being extracted."
                    )
                } else {
                    Text(
                        "Existing project resources can be edited. Archive upload is available when creating a project."
                    )
                }
            }

        case .fileUpload:
            Text("Candidates submit a file. Use a rubric to configure its evaluation.")
        }
    }

    private var isCurrent: Bool {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == bankIdentity.accountID }),
              let current = account.makeScreenClient() else { return false }

        return !isReadOnly && current.taskIdentity == bankIdentity.clientIdentity
    }

    private func prepare() async {
        await model.prepare(questionID: questionID, client: client, identity: bankIdentity)
        teamID = model.draft.teamID?.uuidString ?? ""
    }

    private func save() async {
        model.draft.teamID = UUID(uuidString: teamID.trimmingCharacters(in: .whitespacesAndNewlines))
        if let id = await model.save(client: client, isCurrent: { isCurrent }) {
            onSaved(id)
            dismiss()
        }
    }

    private func upload(_ result: Result<URL, any Error>) async {
        readingArchive = true
        defer { readingArchive = false }
        do {
            let url = try result.get()
            let bytes = try await Task.detached { try ScreenProjectArchiveInput.read(url) }.value
            await model.upload(bytes, filename: url.lastPathComponent, client: client, isCurrent: { isCurrent })
        } catch {
            model.reportFileError(error)
        }
    }
}
