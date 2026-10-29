import Foundation

struct QuestionVariantFileDraft: Identifiable {
    var id = UUID()
    var file = QuestionStarterFileDraft()
    var hidden = false
    var deleted = false

    var requestValue: QuestionVariantFileContent {
        .init(path: file.canonicalPath, contents: deleted ? nil : file.contents, hidden: hidden, deleted: deleted)
    }
}

struct QuestionVariantDraft: Identifiable {
    enum CodeSource: String, CaseIterable, Identifiable {
        case preserve, languageDefault, singleFile, projectFiles

        var id: Self {
            self
        }
    }

    var id = UUID()
    var variantID: Int?
    var originalLanguage: String?
    var isProjectTemplate = false
    var language = "ruby"
    var contents = ""
    var solution = ""
    var originalSolution: String?
    var codeSource: CodeSource = .preserve
    var files: [QuestionVariantFileDraft] = []

    init(variant: QuestionVariant? = nil) {
        guard let variant else { return }

        variantID = variant.id
        originalLanguage = variant.projectTemplateSlug ?? variant.language
        isProjectTemplate = variant.projectTemplateSlug != nil
        language = variant.projectTemplateSlug ?? variant.language ?? ""
        contents = variant.contents ?? ""
        solution = variant.solution ?? ""
        originalSolution = solution
        files = (variant.fileContents ?? []).map {
            QuestionVariantFileDraft(file: .init(path: $0.path, contents: $0.contents ?? ""),
                                     hidden: $0.hidden ?? false, deleted: $0.deleted ?? false)
        }
    }

    var hasInvalidFiles: Bool {
        guard codeSource == .projectFiles else { return false }

        let drafts = files.map(\.file)
        return drafts.hasInvalidStarterFilePaths || files.contains { $0.deleted && $0.file.canonicalPath == ".cpad" }
    }

    var canSave: Bool {
        !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasInvalidFiles
    }

    var mutation: QuestionVariantMutation {
        let code: QuestionVariantContents = switch codeSource {
        case .preserve, .projectFiles: .unchanged
        case .singleFile: .value(contents)
        case .languageDefault: .languageDefault
        }
        return .init(
            language: language == originalLanguage ? nil : language.trimmingCharacters(in: .whitespacesAndNewlines),
            contents: code,
            fileContents: codeSource == .projectFiles ? files.map(\.requestValue) : nil,
            solution: solution == originalSolution ? nil : solution
        )
    }
}
