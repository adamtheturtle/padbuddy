//
//  coderpadTests+WhiteboardDownload.swift
//  coderpadTests
//
//  The bounded whiteboard-image download: what it accepts, what it rejects, and
//  that chunked accumulation still reproduces the body byte for byte (#2092).
//

@testable import CoderPad
import Foundation
import Testing

/// Serves canned bodies for the whiteboard download tests. The path picks the
/// fixture so there is no mutable state to share between parallel tests.
private final nonisolated class WhiteboardMockURLProtocol: URLProtocol {
    /// A deterministic, non-repeating-per-chunk body, so a chunking bug that
    /// dropped or reordered a buffer would change the bytes.
    static func body(count: Int) -> Data {
        Data((0 ..< count).map { UInt8($0 % 251) })
    }

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
        default: (Self.body(count: 200_000), "image/png")
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
    private let textURL = URL(string: "https://example.com/text")!

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WhiteboardMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test
    func `a multi-chunk image body arrives intact`() async throws {
        let data = try await WhiteboardImageCache.fetchBounded(
            url: imageURL,
            maxBytes: 1_000_000,
            session: session
        )
        #expect(data == WhiteboardMockURLProtocol.body(count: 200_000))
    }

    @Test
    func `a body past the budget is rejected`() async {
        let error = await #expect(throws: URLError.self) {
            _ = try await WhiteboardImageCache.fetchBounded(
                url: imageURL,
                maxBytes: 1024,
                session: session
            )
        }
        #expect(error?.code == .dataLengthExceedsMaximum)
    }

    @Test
    func `a non-image response never reaches the decoder`() async {
        let error = await #expect(throws: URLError.self) {
            _ = try await WhiteboardImageCache.fetchBounded(
                url: textURL,
                maxBytes: 1_000_000,
                session: session
            )
        }
        #expect(error?.code == .cannotDecodeContentData)
    }
}
