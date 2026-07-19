//
//  ScreenClient+Webhook.swift
//  coderpad
//

import Foundation
import SafeURLKit

extension ScreenClient {
    private nonisolated static let webhookPolicy = URLPolicy(
        allowedSchemes: ["https"],
        portRule: .any,
        maximumLength: 2048
    )

    /// The currently configured webhook URL, if any. `GET /webhook`.
    nonisolated func webhookURL() async throws -> String? {
        let raw = try await get(WebhookConfig.self, path: "/webhook").url
        return try Self.validatedWebhookURL(raw)
    }

    /// Sets (replacing any existing) the webhook callback URL. `POST /webhook`.
    /// The request body is the URL as a bare JSON string, per the API contract.
    nonisolated func setWebhookURL(_ url: String) async throws {
        guard let url = Self.normalizedWebhookURL(url) else {
            throw CoderPadError.decode("Screen webhook callback must be a public HTTPS URL.")
        }

        try await sendNoContent(method: "POST", path: "/webhook", body: url)
    }

    /// Removes the configured webhook. `DELETE /webhook`.
    nonisolated func deleteWebhook() async throws {
        try await sendNoContent(method: "DELETE", path: "/webhook")
    }

    private nonisolated struct WebhookConfig: Decodable { let url: String? }

    nonisolated static func normalizedWebhookURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return webhookPolicy.allows(trimmed) ? trimmed : nil
    }

    nonisolated static func validatedWebhookURL(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        guard let normalized = normalizedWebhookURL(raw) else {
            throw CoderPadError.decode("Screen returned an invalid webhook callback URL.")
        }

        return normalized
    }
}
