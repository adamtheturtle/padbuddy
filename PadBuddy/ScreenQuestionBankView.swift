import SwiftUI

struct ScreenQuestionBankView: View {
    let client: ScreenClient
    let accountID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var model = ScreenQuestionBankModel()
    @State private var draft = ScreenBankFilterDraft()
    @State private var path: [UUID] = []
    @State private var showingFilters = false
    @State private var showingCreate = false
    @Environment(\.isReadOnly) private var isReadOnly

    var identity: ScreenBankIdentity {
        ScreenBankIdentity(accountID: accountID, clientIdentity: client.taskIdentity)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(model.questions) { question in
                    NavigationLink(value: question.id) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: ScreenBankText.localized(question.title) ?? question.id.uuidString)
                            Text(verbatim: [question.type, question.difficulty, question.programmingLanguageID]
                                .compactMap(\.self).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.loading {
                    ProgressView("Loading Screen questions…")
                } else if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Retry") { Task { await reload() } }
                } else if model.questions.isEmpty {
                    Text("No Screen questions match these filters.").foregroundStyle(.secondary)
                }
                if model.nextStart != nil {
                    Button("Load More Questions") {
                        Task { await model.loadMore(client: client, identity: identity) }
                    }
                    .disabled(model.loading)
                }
            }
            .navigationTitle("Screen Question Bank")
            .navigationDestination(for: UUID.self) { questionID in
                ScreenBankQuestionDetailView(client: client, bankIdentity: identity, questionID: questionID)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .automatic) {
                    Button("New Question", systemImage: "plus") { showingCreate = true }.disabled(isReadOnly)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Filters", systemImage: "line.3.horizontal.decrease") { showingFilters = true }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Reload", systemImage: "arrow.clockwise") { Task { await reload() } }
                        .disabled(model.loading)
                }
            }
        }
        .task(id: identity) { await reload() }
        .sheet(isPresented: $showingCreate) {
            ScreenQuestionAuthoringSheet(client: client, bankIdentity: identity, questionID: nil) { id in
                Task {
                    await model.reload(client: client, identity: identity, filters: draft.filters)
                    path = [id]
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                ScreenQuestionBankFilters(draft: $draft)
                    .navigationTitle("Screen Question Filters")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingFilters = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Apply") {
                                showingFilters = false
                                Task { await reload() }
                            }
                            .disabled(draft.validationMessage != nil)
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 580)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 600)
        #endif
    }

    private func reload() async {
        guard draft.validationMessage == nil else { return }

        path = []
        await model.reload(client: client, identity: identity, filters: draft.filters)
    }
}

enum ScreenBankText {
    static func localized(_ values: [String: String]?, locale: String? = nil) -> String? {
        guard let values else { return nil }

        let preferred = locale ?? Locale.current.language.languageCode?.identifier ?? "en"
        return values[preferred] ?? values["en"] ?? values.keys.min().flatMap { values[$0] }
    }
}

struct ScreenBankQuestionDetailView: View {
    let client: ScreenClient
    let bankIdentity: ScreenBankIdentity
    let questionID: UUID
    @State private var model = ScreenBankDetailModel()
    @State private var insightLanguage = ""
    @State private var showingEdit = false
    @Environment(\.isReadOnly) private var isReadOnly
    @State private var locale = Locale.current.language.languageCode?.identifier ?? "en"

    private var identity: ScreenBankDetailIdentity {
        let language = insightLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScreenBankDetailIdentity(
            bank: bankIdentity,
            questionID: questionID,
            language: language.isEmpty ? nil : language
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let question = model.question, model.identity?.questionID == questionID {
                    questionContent(question)
                    Divider()
                    questionInsights
                }
                if model.loading {
                    ProgressView("Loading question details…")
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: ScreenBankDetailIdentity(bank: bankIdentity, questionID: questionID, language: nil)) {
            await load()
        }
        .navigationTitle("Screen Question")
        .toolbar {
            Button("Edit Question", systemImage: "pencil") { showingEdit = true }
                .disabled(isReadOnly || model.question == nil || model.question?.fromCoderPadQuestionBank == true
                    || model.question?.type.flatMap(ScreenQuestionSave.QuestionType.init(rawValue:)) == nil)
        }
        .sheet(isPresented: $showingEdit) {
            ScreenQuestionAuthoringSheet(client: client, bankIdentity: bankIdentity, questionID: questionID) { _ in
                Task { await load() }
            }
        }
    }

    @ViewBuilder
    private func questionContent(_ question: ScreenQuestionDetails) -> some View {
        Text(verbatim: ScreenBankText.localized(question.title, locale: locale) ?? questionID.uuidString)
            .font(.title2)
        if let locales = question.locales, !locales.isEmpty {
            Picker("Content language", selection: $locale) {
                ForEach(locales, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .onAppear {
                if !locales.contains(locale) {
                    locale = locales[0]
                }
            }
        }
        if let statement = ScreenBankText.localized(question.statement, locale: locale) {
            MarkdownText(statement)
        } else {
            Text("The service did not provide a question statement.").foregroundStyle(.secondary)
        }
        ScreenBankQuestionContent(question: question, locale: locale)
    }

    @ViewBuilder
    private var questionInsights: some View {
        TextField("Insights programming language (optional)", text: $insightLanguage)
        Button("Load Question Insights") { Task { await load() } }.disabled(model.loading)
        if let insights = model.insights {
            ScreenBankInsightsView(insights: insights)
        } else if let error = model.insightsError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else if !model.loading {
            Text("Question insights are not available.").foregroundStyle(.secondary)
        }
    }

    private func load() async {
        await model.load(client: client, identity: identity)
    }
}
