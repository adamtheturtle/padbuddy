import Foundation

struct QuestionVariantFileDraft: Identifiable {
    var id = UUID()
    var file = QuestionStarterFileDraft()
    var hidden = false
    var deleted = false
    var binary: Bool?
    var contentsUnavailable = false

    var requestValue: QuestionVariantFileContent {
        .init(path: file.canonicalPath, contents: deleted || contentsUnavailable ? nil : file.contents,
              hidden: hidden, deleted: deleted, binary: binary)
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
    var hasUnavailableOriginalFiles = false

    init(variant: QuestionVariant? = nil) {
        guard let variant else { return }

        variantID = variant.id
        originalLanguage = variant.projectTemplateSlug ?? variant.language
        isProjectTemplate = variant.projectTemplateSlug != nil
        language = variant.projectTemplateSlug ?? variant.language ?? ""
        contents = variant.contents ?? ""
        solution = variant.solution ?? ""
        originalSolution = solution
        hasUnavailableOriginalFiles = (variant.fileContents ?? []).contains {
            $0.deleted != true && ($0.binary == true || $0.contents == nil)
        }
        files = (variant.fileContents ?? []).map {
            QuestionVariantFileDraft(file: .init(path: $0.path, contents: $0.contents ?? ""),
                                     hidden: $0.hidden ?? false, deleted: $0.deleted ?? false,
                                     binary: $0.binary, contentsUnavailable: $0.binary == true || $0.contents == nil)
        }
    }

    var hasInvalidFiles: Bool {
        guard codeSource == .projectFiles else { return false }

        let drafts = files.map(\.file)
        return drafts.hasInvalidStarterFilePaths || files.contains { $0.deleted && $0.file.canonicalPath == ".cpad" }
    }

    var canSave: Bool {
        let hasEnvironment = !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (variantID != nil && !changesEnvironment && codeSource == .preserve)
        return hasEnvironment && !hasInvalidFiles && !wouldReplaceUnavailableFiles
    }

    var changesEnvironment: Bool {
        language.trimmingCharacters(in: .whitespacesAndNewlines) != (originalLanguage ?? "")
    }

    var wouldReplaceUnavailableFiles: Bool {
        hasUnavailableOriginalFiles && (codeSource != .preserve || changesEnvironment)
    }

    var mutation: QuestionVariantMutation {
        let code: QuestionVariantContents = switch codeSource {
        case .preserve, .projectFiles: .unchanged
        case .singleFile: .value(contents)
        case .languageDefault: .languageDefault
        }
        return .init(
            language: changesEnvironment ? language.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            contents: code,
            fileContents: codeSource == .projectFiles ? files.map(\.requestValue) : nil,
            solution: solution == originalSolution ? nil : solution
        )
    }
}

extension Question {
    var hasBinaryStarterFiles: Bool {
        (fileContents ?? []).contains { $0.binary == true && $0.deleted != true }
    }
}

struct QuestionBinaryReplacementError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Text replacement cannot preserve binary files. Use a complete project ZIP instead.")
    }
}
