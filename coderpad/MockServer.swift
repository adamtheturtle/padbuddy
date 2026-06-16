//
//  MockServer.swift
//  coderpad
//
//  In-process URLProtocol that fakes the CoderPad API with canned data,
//  so the app can run in a demo mode without a real key or network.
//

import Foundation
import Synchronization

nonisolated enum MockServer {
    static let host = "app.coderpad.io"

    /// A session backed by the in-process fake API. When `unauthorized` is true the
    /// server answers every request with 401, which drives the "bad key" demo:
    /// the unauthorized banner and error states can be shown without a real revoked key.
    static func session(unauthorized: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        let proto: URLProtocol.Type = unauthorized ? MockUnauthorizedURLProtocol.self : MockURLProtocol.self
        config.protocolClasses = [proto] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}

/// Answers every CoderPad request with 401 Unauthorized, mimicking a revoked or
/// invalid API key. Backs the "bad key" demo account.
final nonisolated class MockUnauthorizedURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockServer.host
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body = Data(#"{"status":"error","message":"Invalid API key"}"#.utf8)
        let headers = ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final nonisolated class MockURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MockServer.host
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let path = url.path
        let method = request.httpMethod ?? "GET"
        let bodyData = request.httpBody ?? Self.drain(stream: request.httpBodyStream)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]

        // Route to the per-API-key state (carried in the Authorization header the
        // client sets on every request), so each client — the app's demo account,
        // and each test — sees an isolated store.
        let state = MockStateRegistry.state(forKey: Self.apiKey(from: request))
        let (status, body) = MockResponses.respond(state: state,
                                                   method: method,
                                                   path: path,
                                                   query: query,
                                                   body: bodyData)

        let headers = ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The API key from the request's `Authorization: Bearer <key>` header, used to
    /// pick the request's `MockState`. Falls back to "demo" when absent so a stray
    /// unauthenticated request still resolves to a valid store.
    private static func apiKey(from request: URLRequest) -> String {
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let key = header.hasPrefix("Bearer ") ? String(header.dropFirst("Bearer ".count)) : header
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
