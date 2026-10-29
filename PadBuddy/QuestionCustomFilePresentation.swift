import Foundation

nonisolated struct QuestionCustomFilePresentation {
    static let maximumFiles = 100
    let name: String
    let description: String
    let size: String

    init(_ file: QuestionCustomFile) {
        let filename = ExternalText.singleLine(file.filename ?? "", limit: 256)
        let title = ExternalText.singleLine(file.title ?? "", limit: 256)
        name = !filename.isEmpty ? filename : (!title.isEmpty ? title : String(localized: "Untitled file"))
        description = ExternalText.singleLine(file.description ?? "", limit: 512)
        size = ExternalText.singleLine(file.filesize ?? "", limit: 40)
    }
}
