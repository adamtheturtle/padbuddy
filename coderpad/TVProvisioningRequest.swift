import Foundation

func companionStatusBelongsToAccount(statusAccountID: UUID?, accountID: UUID) -> Bool {
    statusAccountID == accountID
}

nonisolated enum WatchProvisioningReplyError: String {
    case invalidPayload = "invalid_payload"
    case saveFailed = "save_failed"
}

nonisolated struct TVProvisioningRequest: Equatable {
    private static let serverKey = "server"
    private static let apiKeyKey = "apiKey"

    let server: URL
    let apiKey: String

    init?(dictionary: [String: Any]) {
        guard let serverText = dictionary[Self.serverKey] as? String,
              let key = dictionary[Self.apiKeyKey] as? String else { return nil }

        self.init(serverText: serverText, apiKey: key)
    }

    private init?(serverText: String, apiKey keyText: String) {
        guard let server = URL(string: serverText), server.scheme == "https", server.host != nil,
              server.user == nil, server.password == nil, server.query == nil,
              server.fragment == nil else { return nil }
        guard let key = Self.validatedAPIKey(keyText) else { return nil }

        self.server = server
        apiKey = key
    }

    static func payload(server: URL, apiKey: String) -> [String: String]? {
        guard let apiKey = validatedAPIKey(apiKey) else { return nil }

        return [
            serverKey: server.absoluteString,
            apiKeyKey: apiKey
        ]
    }

    private static func validatedAPIKey(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUnsafeScalar = value.unicodeScalars.contains {
            let category = $0.properties.generalCategory
            return category == .control || category == .format
        }
        return value.isEmpty || value.utf8.count > 4096 || hasUnsafeScalar ? nil : value
    }
}

#if os(iOS)
    extension TVProvisioningRequest {
        static func payload(for account: Account) -> [String: String]? {
            guard !account.isMock else { return nil }
            guard !account.hasMalformedBaseURLOverride else { return nil }

            return payload(server: account.resolvedBaseURL, apiKey: account.apiKey)
        }
    }
#endif
