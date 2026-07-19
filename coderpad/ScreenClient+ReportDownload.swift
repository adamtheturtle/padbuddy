//
//  ScreenClient+ReportDownload.swift
//  coderpad
//

import Foundation

extension ScreenClient {
    /// Downloads report bytes to URLSession's temporary file, checking both the
    /// advertised and actual size before materializing the PDF in memory (#2767).
    nonisolated func reportData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let fileURL: URL
        let response: URLResponse
        do {
            (fileURL, response) = try await session.download(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            throw CoderPadError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CoderPadError.http(0, "No HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = (try? Data(contentsOf: fileURL, options: .mappedIfSafe)) ?? Data()
            let bounded = body.prefix(Self.maximumErrorBodyBytes)
            throw CoderPadError.http(http.statusCode, String(bytes: bounded, encoding: .utf8) ?? "")
        }

        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard Self.isAllowedReportSize(declared: http.expectedContentLength, actual: fileSize) else {
            throw CoderPadError.decode("The report is too large to open.")
        }

        return try (Data(contentsOf: fileURL), http)
    }

    nonisolated static func isAllowedReportSize(declared: Int64, actual: Int) -> Bool {
        let maximum = Int64(ScreenReportFiles.maxReportBytes)
        return actual >= 0 && Int64(actual) <= maximum
            && (declared < 0 || declared <= maximum)
    }
}
