import SwiftUI

struct QuestionVariantsScope: Hashable {
    let questionID: Int
    let accountID: UUID?
    let clientIdentity: ClientTaskIdentity
}

struct QuestionVariantsView: View {
    let client: CoderPadClient
    let questionID: Int
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var variants: [QuestionVariant] = []
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var isActive = false
    @State private var error: String?
    @State private var draft: QuestionVariantDraft?
    @State private var pendingDeletion: QuestionVariant?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error {
                Text(verbatim: error).foregroundStyle(.red).textSelection(.enabled)
            }
            if isLoading {
                ProgressView("Loading variants…")
            } else if variants.isEmpty {
                ContentUnavailableView("No Variants", systemImage: "square.stack",
                                       description: Text("Add code and a solution for another environment."))
            } else {
                ForEach(variants) { variant in
                    variantRow(variant)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            isActive = true
            await load()
        }
        .onDisappear { isActive = false }
        .sheet(item: $draft) { draft in
            QuestionVariantEditor(client: client, questionID: questionID, draft: draft) { saved in
                guard isActive else { return }

                if let index = variants.firstIndex(where: { $0.id == saved.id }) {
                    variants[index] = saved
                } else {
                    variants.append(saved)
                }
            }
        }
        .confirmationDialog("Delete This Variant?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: {
                if !$0 {
                    pendingDeletion = nil
                }
            }
        ), titleVisibility: .visible) {
            if let variant = pendingDeletion {
                Button("Delete Variant", role: .destructive) {
                    Task { await delete(variant) }
                }
            }
        } message: {
            Text("The variant’s starter code and solution will be deleted.")
        }
    }

    private var header: some View {
        HStack {
            SectionHeader(title: "Variants", systemImage: "square.stack")
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || isWorking)
            Button {
                draft = QuestionVariantDraft()
            } label: {
                Label("Add Variant", systemImage: "plus")
            }
            .disabled(isReadOnly || isWorking || isLoading)
        }
    }

    private func variantRow(_ variant: QuestionVariant) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: variant.display ?? variant.projectTemplateSlug ?? variant.language
                    ?? String(localized: "Unknown")).font(.headline)
                Spacer()
                Button("Edit") { Task { await edit(variant) } }
                    .disabled(isReadOnly || isWorking || isLoading)
                Button(role: .destructive) { pendingDeletion = variant } label: {
                    Label("Delete Variant", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .disabled(isReadOnly || isWorking || isLoading)
            }
            if let contents = variant.contents {
                if contents.isEmpty {
                    Text("Blank starter code").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: contents).font(.callout.monospaced()).textSelection(.enabled)
                        .lineLimit(8)
                }
            } else if variant.projectTemplateSlug == nil {
                Text("Uses the language’s default starter code").foregroundStyle(.secondary)
            }
            if let files = variant.fileContents {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    HStack {
                        Label { Text(verbatim: file.path) } icon: { Image(systemName: "doc") }
                        if file.hidden == true {
                            Text("Hidden").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await client.listQuestionVariants(questionID: questionID)
            guard isActive, !Task.isCancelled else { return }
            guard fetched.allSatisfy({ $0.questionID == questionID }) else {
                throw URLError(.badServerResponse)
            }

            variants = fetched
            error = nil
        } catch {
            guard isActive, !Task.isCancelled else { return }

            self.error = error.localizedDescription
        }
    }

    private func edit(_ variant: QuestionVariant) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let fetched = try await client.getQuestionVariant(questionID: questionID, id: variant.id)
            guard isActive else { return }
            guard fetched.questionID == questionID, fetched.id == variant.id else {
                throw URLError(.badServerResponse)
            }

            draft = QuestionVariantDraft(variant: fetched)
            error = nil
        } catch {
            if isActive {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete(_ variant: QuestionVariant) async {
        guard !isReadOnly, !isWorking else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            try await client.deleteQuestionVariant(questionID: questionID, id: variant.id)
            guard isActive else { return }

            variants.removeAll { $0.id == variant.id }
            error = nil
        } catch {
            if isActive {
                self.error = error.localizedDescription
            }
        }
    }
}
