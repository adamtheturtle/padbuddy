//
//  PadBuddyTests+ScreenCancellation.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen cancellation")
struct ScreenCancellationTests {
    private actor ConcurrencyTracker {
        private(set) var maximum = 0
        private var active = 0

        func enter() {
            active += 1
            maximum = max(maximum, active)
        }

        func leave() {
            active -= 1
        }
    }

    @Test
    func `report limiter caps concurrent operations`() async throws {
        let limiter = ScreenReportOperationLimiter(maximumConcurrentOperations: 2)
        let tracker = ConcurrencyTracker()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try await limiter.perform {
                        await tracker.enter()
                        try await Task.sleep(for: .milliseconds(20))
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(await tracker.maximum == 2)
    }

    @Test
    func `cancelled transport remains task cancellation`() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancelledScreenURLProtocol.self]
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: configuration))

        await #expect(throws: CancellationError.self) {
            _ = try await client.listCampaigns()
        }
    }

    @Test
    func `HTTP errors retain only a bounded response-body prefix`() async {
        do {
            _ = try await screenClient().getTest(id: 999_999)
            Issue.record("Expected the mock server error")
        } catch let CoderPadError.http(code, body) {
            #expect(code == 451)
            #expect(body.utf8.count <= ScreenClient.maximumErrorBodyBytes)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `a loose PDF-like media type is rejected`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().testReport(id: 424_243)
        }
    }

    @Test
    func `full pagination stops ever-new offsets at its page cap`() async {
        do {
            _ = try await screenClient().listAllTests(campaignID: 888)
            Issue.record("Expected the Screen page cap to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("maximum page count"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `full pagination rejects an unseen backward offset`() async {
        do {
            _ = try await screenClient().listAllTests(campaignID: 889)
            Issue.record("Expected backward pagination to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("invalid next offset"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `full pagination rejects a changing total`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().listAllTests(campaignID: 990)
        }
    }

    @Test
    func `full pagination rejects an incomplete terminal snapshot`() async {
        await #expect(throws: CoderPadError.self) {
            _ = try await screenClient().listAllTests(campaignID: 991)
        }
    }

    @Test(arguments: [
        "http://screen.example.com",
        "https://screen.example.com",
        "file:///tmp/screen",
        "https://user:password@screen.example.com",
        "https://screen.example.com/tenant",
        "https://screen.example.com?key=value",
        "https://screen.example.com/#fragment"
    ])
    func `unsafe base URLs are rejected before credentials are attached`(rawURL: String) async throws {
        let url = try #require(URL(string: rawURL))
        let client = ScreenClient(apiKey: "secret", baseURL: url, session: URLSession(configuration: .ephemeral))

        do {
            _ = try await client.listCampaigns()
            Issue.record("Expected an unsafe Screen base URL to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("credential-free HTTPS origin"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `only the configured Screen regional origins are accepted`() throws {
        #expect(ScreenClient.isAllowedBaseURL(ScreenClient.defaultBaseURL))
        #expect(ScreenClient.isAllowedBaseURL(ScreenClient.euBaseURL))
        #expect(try !ScreenClient.isAllowedBaseURL(#require(URL(string: "https://www.codingame.com:8443"))))
    }
}

final nonisolated class CancelledScreenURLProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}

@Suite("Screen report permit cancellation (#4557)")
struct ScreenReportPermitCancellationTests {
    private actor Started {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }

    private func waitForQueuedWaiter(_ limiter: ScreenReportOperationLimiter) async throws {
        while await !limiter.hasQueuedWaiters {
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func `a waiter cancelled while queued never starts its operation`() async throws {
        let limiter = ScreenReportOperationLimiter(maximumConcurrentOperations: 1)
        let started = Started()
        let gate = PermitGate()
        // Occupy the only permit so the next operation has to queue behind it.
        let holder = Task { try await limiter.perform { await gate.wait() } }
        let queued = Task { try await limiter.perform { await started.record() } }
        try await waitForQueuedWaiter(limiter)

        queued.cancel()
        await gate.open()
        _ = try? await holder.value

        await #expect(throws: CancellationError.self) { try await queued.value }
        let count = await started.count
        #expect(count == 0)
    }

    @Test func `the permit a cancelled waiter declines goes to the next waiter`() async throws {
        let limiter = ScreenReportOperationLimiter(maximumConcurrentOperations: 1)
        let started = Started()
        let gate = PermitGate()
        let holder = Task { try await limiter.perform { await gate.wait() } }
        let survivor = Task { try await limiter.perform { await started.record() } }
        try await waitForQueuedWaiter(limiter)

        await gate.open()
        _ = try? await holder.value
        try await survivor.value

        let count = await started.count
        #expect(count == 1)
    }
}

/// A one-shot gate a test holds an operation open with.
actor PermitGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }

        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
