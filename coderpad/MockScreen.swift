//
//  MockScreen.swift
//  coderpad
//
//  In-process URLProtocol that fakes the CoderPad Screen API with canned data, so
//  the Demo account can exercise the full Screen UI (campaigns, test sessions,
//  reports, invitations, webhook) without a real Screen key or network. The
//  Interview API has its own mock in MockServer.swift; Screen is a separate product
//  on a different host with `API-Key` auth, so it gets its own protocol and store.
//

import Foundation

nonisolated enum MockScreen {
    /// The host the mock Screen client points at; `MockScreenURLProtocol` answers for
    /// it. A dedicated demo host (not the live codingame.com/.eu) so a misrouted live
    /// request can never accidentally be served canned data.
    static let host = "screen.mock.coderpad.io"
    static let baseURL = URL.staticURL("https://screen.mock.coderpad.io")

    /// A session backed by the in-process fake Screen API. When `unauthorized` is true
    /// the server answers every request with 401, driving the bad-key demo's Screen
    /// error states without a real revoked key.
    static func session(unauthorized: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        let proto: URLProtocol.Type = unauthorized
            ? MockScreenUnauthorizedURLProtocol.self
            : MockScreenURLProtocol.self
        config.protocolClasses = [proto] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}

extension ScreenClient {
    /// A Screen client backed by the in-process mock (answering 401 for the bad-key
    /// demo). `key` selects the per-client mock store (see `MockScreenState`): it
    /// defaults to "demo" so the app's demo account shares one session store, while
    /// tests can pass a unique key each to stay isolated.
    static func mock(unauthorized: Bool = false, key: String = "demo") -> Self {
        Self(apiKey: key,
             baseURL: MockScreen.baseURL,
             session: MockScreen.session(unauthorized: unauthorized))
    }
}

/// Answers every Screen request with 401 Unauthorized, mimicking a revoked or invalid
/// API key. Backs the bad-key demo account's Screen section.
final nonisolated class MockScreenUnauthorizedURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockScreen.host
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body = Data(#"{"code":"unauthorized","message":"Invalid API key"}"#.utf8)
        guard let response = HTTPURLResponse(
            url: url, statusCode: 401, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final nonisolated class MockScreenURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockScreen.host
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let bodyData = request.httpBody ?? Self.drain(stream: request.httpBodyStream)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        // Route to the per-API-key state (carried in the `API-Key` header the Screen
        // client sets on every request), so the demo account and each test see an
        // isolated store, mirroring MockURLProtocol's per-key isolation.
        let state = MockScreenStateRegistry.state(forKey: Self.apiKey(from: request))
        let result = MockScreenResponses.respond(state: state,
                                                  method: method,
                                                  path: url.path,
                                                  query: query,
                                                  body: bodyData)

        guard let response = HTTPURLResponse(
            url: url, statusCode: result.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": result.contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The Screen API key from the request's `API-Key` header, used to pick the
    /// request's `MockScreenState`. Falls back to "demo" when absent.
    private static func apiKey(from request: URLRequest) -> String {
        let key = request.value(forHTTPHeaderField: "API-Key") ?? ""
        return key.isEmpty ? "demo" : key
    }

    private static func drain(stream: InputStream?) -> Data? {
        guard let stream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
