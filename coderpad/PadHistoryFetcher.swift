//
//  PadHistoryFetcher.swift
//  coderpad
//

import CoderPadKit
import Foundation

final nonisolated class PadHistoryRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let accountBaseURL: URL

    init(accountBaseURL: URL) {
        self.accountBaseURL = accountBaseURL
    }

    func urlSession(_: URLSession, task _: URLSessionTask,
                    willPerformHTTPRedirection _: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.isAllowed(request.url, accountBaseURL: accountBaseURL) ? request : nil)
    }

    static func isAllowed(_ url: URL?, accountBaseURL: URL) -> Bool {
        guard let url else { return false }

        return PadHistoryURLValidation.isAllowed(url.absoluteString, accountBaseURL: accountBaseURL)
    }
}

nonisolated enum PadHistoryFetcher {
    enum FetchError: Error, Equatable {
        case httpStatus(Int)

        var isOptionalMissingHistory: Bool {
            switch self {
            case .httpStatus(404), .httpStatus(410): true
            default: false
            }
        }
    }

    static func fetch(_ urlString: String, accountBaseURL: URL) async throws -> PadHistory {
        guard PadHistoryURLValidation.isAllowed(urlString, accountBaseURL: accountBaseURL),
              let url = URL(string: urlString) else { throw URLError(.unsupportedURL) }

        let delegate = PadHistoryRedirectDelegate(accountBaseURL: accountBaseURL)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200 ... 299).contains(response.statusCode) else {
            throw FetchError.httpStatus(response.statusCode)
        }

        return try JSONDecoder().decode(PadHistory?.self, from: data) ?? PadHistory()
    }
}
