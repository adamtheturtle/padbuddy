//
//  PaginationValidation.swift
//  CoderPadToolCore
//
//  Shared MCP argument validation for user-supplied pagination. The remote APIs have
//  different conventions: Interview list tools use 1-based pages, while Screen uses
//  zero-based offsets plus a positive limit.
//

public func pageValidationError(_ page: Int?) -> String? {
    guard let page, page < 1 else { return nil }

    return "page must be greater than or equal to 1."
}

public func screenPaginationValidationError(start: Int?, limit: Int?) -> String? {
    if let start, start < 0 {
        return "start must be greater than or equal to 0."
    }
    if let limit, limit < 1 {
        return "limit must be greater than or equal to 1."
    }
    return nil
}
