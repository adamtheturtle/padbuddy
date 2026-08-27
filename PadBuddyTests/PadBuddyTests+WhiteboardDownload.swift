//
//  PadBuddyTests+WhiteboardDownload.swift
//  PadBuddyTests
//
//  The Nuke whiteboard pipeline: what it accepts and what it rejects.
//

import Foundation
@testable import PadBuddy
import Testing
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Serves canned bodies for the whiteboard download tests. The path picks the
/// fixture so there is no mutable state to share between parallel tests.
private final nonisolated class WhiteboardMockURLProtocol: URLProtocol {
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL6WQAAAABJRU5ErkJggg==") ?? Data()

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }

        let (data, mime): (Data, String) = switch url.path {
        case "/text": (Data("not an image".utf8), "text/html")
        case "/large": (Data(repeating: 0, count: 200_000), "image/png")
        default: (Self.onePixelPNG, "image/png")
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"]
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Whiteboard bounded download")
struct WhiteboardDownloadTests {
    private let imageURL = URL(string: "https://example.com/image.png")!
    private let largeURL = URL(string: "https://example.com/large")!
    private let textURL = URL(string: "https://example.com/text")!

    private var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WhiteboardMockURLProtocol.self]
        return config
    }

    @MainActor @Test
    func `an image response is decoded through the pipeline`() async throws {
        let cache = WhiteboardImageCache(urlConfiguration: configuration)
        let request = WhiteboardImageCache.request(url: imageURL, maxPixelSize: 100)
        let entry = try await cache.load(request)
        #expect(entry.image.size.width > 0)
        #expect(entry.image.size.height > 0)
        #expect(cache.image(for: request) != nil)

        cache.clear()
        #expect(cache.image(for: request) == nil)
    }

    @MainActor @Test
    func `a body past the budget is rejected`() async {
        let cache = WhiteboardImageCache(urlConfiguration: configuration, maxDownloadBytes: 1024)
        await #expect(throws: (any Error).self) {
            _ = try await cache.load(WhiteboardImageCache.request(url: largeURL, maxPixelSize: 100))
        }
    }

    @MainActor @Test
    func `a non-image response never reaches the decoder`() async {
        let cache = WhiteboardImageCache(urlConfiguration: configuration)
        await #expect(throws: (any Error).self) {
            _ = try await cache.load(WhiteboardImageCache.request(url: textURL, maxPixelSize: 100))
        }
    }
}
