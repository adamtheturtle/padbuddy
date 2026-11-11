import SwiftUI

/// Fetch details only when requested, including when editing is unavailable.
struct QuestionVariantStarterPreview: View {
    let client: CoderPadClient
    let questionID: Int
    let variantID: Int
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Preview Starter Files", isExpanded: $expanded) {
            if expanded {
                QuestionVariantStarterDetails(client: client, questionID: questionID, variantID: variantID)
                    .id(Scope(client: client.taskIdentity, questionID: questionID, variantID: variantID))
            }
        }
    }

    private struct Scope: Hashable {
        let client: ClientTaskIdentity
        let questionID: Int
        let variantID: Int
    }
}

struct QuestionVariantStarterDetails: View {
    let client: CoderPadClient
    let questionID: Int
    let variantID: Int
    @State private var variant: QuestionVariant?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let variant {
                QuestionProjectFilesView(client: client, template: variant.projectTemplateSlug ?? variant.language,
                                         files: (variant.fileContents ?? []).map(\.starterFile))
            } else if failed {
                Text("Variant starter files unavailable").foregroundStyle(.secondary)
                Button("Retry") { Task { await load() } }
            } else {
                ProgressView("Loading starter files…")
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            let fetched = try await client.getQuestionVariant(questionID: questionID, id: variantID)
            guard !Task.isCancelled else { return }
            guard fetched.id == variantID, fetched.questionID == questionID else {
                throw URLError(.badServerResponse)
            }

            variant = fetched
        } catch {
            guard !Task.isCancelled else { return }

            failed = true
        }
    }
}

extension QuestionVariantFileContent {
    var starterFile: QuestionStarterFile {
        .init(path: path, contents: contents, hidden: hidden, deleted: deleted, binary: binary)
    }
}
