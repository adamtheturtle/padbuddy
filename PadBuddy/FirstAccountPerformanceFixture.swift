import CoderPadKitMock
import Foundation
#if DEBUG
    import Synchronization
#endif

extension CoderPadClient {
    static func mockForAppDemo(unauthorized: Bool, key: String) -> Self {
        #if DEBUG
            if coderpadIsUITesting, ProcessInfo.processInfo.arguments.contains("-uiTesting100Pads"), !unauthorized {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [FirstAccountPerformanceProtocol.self]
                return Self(apiKey: key, session: URLSession(configuration: configuration))
            }
        #endif
        return .mock(unauthorized: unauthorized, key: key)
    }
}

#if DEBUG
    /// The explicit UI-performance fixture keeps every non-list request on the SDK's
    /// in-process mock transport. It never forwards a request to the live network.
    private final nonisolated class FirstAccountPerformanceProtocol: URLProtocol, @unchecked Sendable {
        private let state = Mutex((task: Task<Void, Never>?.none, stopped: false))

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let request = request
            let task = Task {
                do {
                    let data: Data
                    let response: URLResponse
                    if request.url?.path == "/api/pads", request.httpMethod == "GET", let url = request.url {
                        let pads = (1 ... 100).map { index in
                            ["id": String(format: "PERF%04d", index),
                             "title": String(format: "Performance Pad %03d", index),
                             "state": "started", "language": "python3"]
                        }
                        data = try JSONSerialization.data(withJSONObject: [
                            "status": "OK", "pads": pads, "total": 100, "next_page": NSNull()
                        ])
                        guard let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                         headerFields: ["Content-Type": "application/json"]) else {
                            return
                        }

                        response = http
                    } else {
                        (data, response) = try await MockServer.session().data(for: request)
                    }
                    guard !Task.isCancelled else { return }

                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: data)
                    client?.urlProtocolDidFinishLoading(self)
                } catch {
                    if !Task.isCancelled {
                        client?.urlProtocol(self, didFailWithError: error)
                    }
                }
            }
            state.withLock {
                $0.task = task
                if $0.stopped {
                    task.cancel()
                }
            }
        }

        override func stopLoading() {
            state.withLock { $0.stopped = true; $0.task?.cancel() }
        }
    }
#endif
