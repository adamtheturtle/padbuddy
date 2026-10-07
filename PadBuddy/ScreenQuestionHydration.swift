import Foundation

enum ScreenQuestionHydration {
    static func editable(_ question: ScreenQuestionDetails) throws -> ScreenQuestionSave {
        guard question.fromCoderPadQuestionBank != true else {
            throw CoderPadError.decode(String(localized: "Questions from the CoderPad bank are read-only."))
        }

        return try input(question)
    }

    static func required<T: RawRepresentable>(_ raw: String?, as _: T.Type) throws -> T
        where T.RawValue == String {
        guard let raw, let value = T(rawValue: raw) else {
            throw CoderPadError
                .decode(String(localized: "This question contains a value the editor does not support."))
        }

        return value
    }

    static func optional<T: RawRepresentable>(_ raw: String?, as type: T.Type) throws -> T?
        where T.RawValue == String {
        try raw.map { try required($0, as: type) }
    }
}
