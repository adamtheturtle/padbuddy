//
//  ScreenWebhookDeliveryTest.swift
//  coderpad
//

import Foundation
import SafeURLKit

enum ScreenWebhookDeliveryTest {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Sends a harmless synthetic event before Screen is configured to use the
    /// endpoint. Requiring a successful HTTP response catches unreachable or
    /// rejecting endpoints without changing the saved webhook first.
    nonisolated static func send(to value: String) async throws {
        guard let normalized = ScreenClient.normalizedWebhookURL(value),
              let url = URL(string: normalized) else {
            throw Failure(errorDescription: String(localized: "Enter a valid public https:// URL."))
        }

        let validated: ValidatedURL
        do {
            validated = try URLPolicy.publicHTTPS.validate(url)
        } catch {
            throw Failure(errorDescription: String(localized: "Enter a valid public https:// URL."))
        }

        var request = URLRequest(url: validated.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PadBuddy webhook delivery test", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "event": "padbuddy.webhook_test",
            "source": "PadBuddy",
            "test": true
        ])

        // Reject private-network and HTTPS→HTTP redirects (#4558, #4559).
        let redirectDelegate = PolicyEnforcingRedirectDelegate(policy: .publicHTTPS)
        let session = URLSession(
            configuration: .ephemeral, delegate: redirectDelegate, delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(errorDescription: String(localized: "The webhook test did not receive an HTTP response."))
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Failure(errorDescription:
                String(localized: "The webhook test returned HTTP \(http.statusCode). Nothing was saved."))
        }
    }
}
