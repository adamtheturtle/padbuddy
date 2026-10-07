import SwiftUI

struct ScreenQuestionBankFilters: View {
    @Binding var draft: ScreenBankFilterDraft

    var body: some View {
        Form {
            TextField("Question type", text: $draft.type)
            TextField("Minimum duration in seconds", text: $draft.minimumDuration)
            TextField("Maximum duration in seconds", text: $draft.maximumDuration)
            Picker("Difficulty", selection: $draft.difficulty) {
                Text("All").tag(ScreenQuestionFilters.Difficulty?.none)
                ForEach(ScreenQuestionFilters.Difficulty.allCases, id: \.self) {
                    Text(verbatim: $0.rawValue).tag(Optional($0))
                }
            }
            TextField("Domain", text: $draft.domain)
            TextField("Skill", text: $draft.skill)
            TextField("Programming language", text: $draft.language)
            Picker("Question origin", selection: $draft.bankOrigin) {
                Text("All").tag(Bool?.none)
                Text("CoderPad question bank").tag(Bool?.some(true))
                Text("Organization questions").tag(Bool?.some(false))
            }
            Picker("Product", selection: $draft.product) {
                Text("All").tag(ScreenQuestionFilters.Product?.none)
                ForEach(ScreenQuestionFilters.Product.allCases, id: \.self) {
                    Text(verbatim: $0.rawValue).tag(Optional($0))
                }
            }
            Picker("Sort", selection: $draft.sort) {
                Text("Default").tag(ScreenQuestionFilters.Sort?.none)
                ForEach(ScreenQuestionFilters.Sort.allCases, id: \.self) {
                    Text(sortLabel($0)).tag(Optional($0))
                }
            }
            Picker("Order", selection: $draft.order) {
                Text("Default").tag(ScreenQuestionFilters.Order?.none)
                Text("Ascending").tag(ScreenQuestionFilters.Order?.some(.asc))
                Text("Descending").tag(ScreenQuestionFilters.Order?.some(.desc))
            }
            if let message = draft.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }

    private func sortLabel(_ sort: ScreenQuestionFilters.Sort) -> LocalizedStringKey {
        switch sort {
        case .id: "Question ID"
        case .title: "Title"
        case .type: "Question type"
        case .durationSeconds: "Duration"
        case .difficulty: "Difficulty"
        case .domain: "Domain"
        case .skill: "Skill"
        default: remainingSortLabel(sort)
        }
    }
}

private func remainingSortLabel(_ sort: ScreenQuestionFilters.Sort) -> LocalizedStringKey {
    switch sort {
    case .programmingLanguage: "Programming language"
    case .modificationTime: "Last modified"
    case .fromCoderPadQuestionBank: "Question origin"
    default: "Product"
    }
}
