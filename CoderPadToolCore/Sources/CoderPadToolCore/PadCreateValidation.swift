//
//  PadCreateValidation.swift
//  CoderPadToolCore
//
//  Shared validation for create_pad inputs used by both MCP servers.
//

public func padSeedValidationError(questionID: Int?, contents: String?) -> String? {
    guard questionID != nil, contents != nil else { return nil }

    return "question_id and contents are mutually exclusive; provide only one seed source."
}
