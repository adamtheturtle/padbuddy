//
//  coderpadTests+Screen+UnstablePaginationMock.swift
//  coderpadTests
//

nonisolated extension ScreenAPIMockURLProtocol {
    static let changingTotalPage1JSON = #"""
    {"tests":[{"id":50}],"pagination":{"start":0,"limit":1,"total":2,"has_more_items":true,"next_start":1}}
    """#

    static let changingTotalPage2JSON = #"""
    {"tests":[{"id":51}],"pagination":{"start":1,"limit":1,"total":3,"has_more_items":false}}
    """#

    static let incompleteTerminalPageJSON = #"""
    {"tests":[{"id":60}],"pagination":{"start":0,"limit":1,"total":2,"has_more_items":false}}
    """#
}
