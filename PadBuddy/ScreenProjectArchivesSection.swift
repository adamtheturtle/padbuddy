import SwiftUI
import UniformTypeIdentifiers

struct ScreenProjectArchivesSection: View {
    let client: ScreenClient
    let session: ScreenTestSession
    @State private var selected: UUID?
    @State private var model = ScreenProjectArchiveModel()

    private var projects: [ScreenDetailedQuestion] {
        session.detailedQuestions.filter { $0.type == "PROJECT" }
    }

    private var identity: ScreenProjectArchiveIdentity? {
        let questionID = selected.flatMap { id in projects.contains { $0.id == id } ? id : nil } ?? projects.first?
            .id
        return questionID.map {
            ScreenProjectArchiveIdentity(clientIdentity: client.taskIdentity, testID: session.id, questionID: $0)
        }
    }

    var body: some View {
        DetailSection(title: "Screen Project Archives", systemImage: "doc.zipper") {
            VStack(alignment: .leading, spacing: 12) {
                if !projects.isEmpty {
                    Picker(
                        "Project question",
                        selection: Binding(get: { identity?.questionID }, set: { selected = $0 })
                    ) {
                        ForEach(projects) { question in
                            Text(verbatim: question.title ?? question.id.uuidString).tag(Optional(question.id))
                        }
                    }
                }
                if let identity {
                    Text(verbatim: identity.questionID.uuidString).font(.caption).textSelection(.enabled)
                    Button("Download Candidate Project…", systemImage: "square.and.arrow.down") {
                        Task { await model.download(client: client, identity: identity) }
                    }.disabled(model.downloading || model.identity != identity)
                    Text("The tar.gz archive contains the candidate’s project changes. Choose where to save it.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No UUID project question results are available for this session.")
                        .foregroundStyle(.secondary)
                }
                if model.downloading {
                    ProgressView("Downloading project archive…")
                }
                if model.identity == identity, let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("Try downloading again when the candidate’s project is available.").font(.caption)
                }
            }
        }
        .task(id: identity) { model.reset(identity: identity) }
        .onChange(of: identity) { _, new in model.reset(identity: new) }
        .fileExporter(
            isPresented: Binding(get: { model.document != nil && model.identity == identity }, set: { presented in
                if !presented {
                    model.dismissExport()
                }
            }),
            document: model.identity == identity ? model.document : nil,
            contentType: .gzip, defaultFilename: identity?.filename
        ) { result in model.completed(result, identity: identity) }
    }
}
