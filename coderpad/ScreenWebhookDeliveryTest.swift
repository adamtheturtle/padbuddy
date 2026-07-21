//
//  ScreenWebhookDeliveryTest.swift
//  coderpad
//

import Foundation

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
            throw Failure(errorDescription: "Enter a valid public https:// URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PadBuddy webhook delivery test", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "event": "padbuddy.webhook_test",
            "source": "PadBuddy",
            "test": true
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(errorDescription: "The webhook test did not receive an HTTP response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Failure(errorDescription:
                "The webhook test returned HTTP \(http.statusCode). Nothing was saved.")
        }
    }
}
