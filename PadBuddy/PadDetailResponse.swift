//
//  PadDetailResponse.swift
//  coderpad
//

nonisolated enum PadDetailResponse {
    static func matches(requestedID: String, responseID: String?) -> Bool {
        requestedID == responseID
    }
}

nonisolated enum PadDetailResponseError: Error {
    case mismatchedID
}
