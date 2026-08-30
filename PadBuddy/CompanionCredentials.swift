//
//  CompanionCredentials.swift
//  coderpad
//
//  The server and API key a companion app was provisioned with, as one committed value.
//

import Foundation

/// A companion's provisioned backend and the key for it.
///
/// Provisioning used to save the key to the Keychain and then write the server URL to
/// UserDefaults as a separate step. A crash, a defaults write failure, or an interruption
/// between the two paired a *new* key with the *old* server, and the next reload sent that
/// secret to the wrong backend (#4654). Encoding both into the single Keychain item makes
/// the pair change in one write or not at all.
nonisolated struct CompanionCredentials: Equatable {
    let server: URL
    let apiKey: String

    /// `<server>\n<api key>`. The server is a validated absolute HTTPS URL, so it can
    /// contain no newline, which makes the first one an unambiguous separator.
    var encoded: Data {
        Data("\(server.absoluteString)\n\(apiKey)".utf8)
    }

    init(server: URL, apiKey: String) {
        self.server = server
        self.apiKey = apiKey
    }

    init?(encoded data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              let separator = text.firstIndex(of: "\n") else { return nil }

        let serverText = String(text[text.startIndex ..< separator])
        let storedKey = String(text[text.index(after: separator)...])
        guard let candidate = URL(string: serverText),
              let server = TVProvisioningRequest.validatedPersistedServer(candidate),
              let key = TVProvisioningRequest.validatedAPIKey(storedKey) else { return nil }

        self.init(server: server, apiKey: key)
    }

    /// Reads a pre-#4654 item, where the Keychain held the key alone and the server lived
    /// in UserDefaults. Returns nil unless both halves are present and valid, so a
    /// half-written legacy pair is not adopted.
    static func legacy(apiKeyData: Data, storedServer: URL?) -> Self? {
        guard let storedKey = String(data: apiKeyData, encoding: .utf8),
              let key = TVProvisioningRequest.validatedAPIKey(storedKey),
              let storedServer, let server = TVProvisioningRequest.validatedPersistedServer(storedServer)
        else { return nil }

        return Self(server: server, apiKey: key)
    }
}
