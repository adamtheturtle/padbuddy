import Foundation

func companionStatusBelongsToAccount(statusAccountID: UUID?, accountID: UUID) -> Bool {
    statusAccountID == accountID
}

func companionSuccessIsStale(isSuccess: Bool, isAvailable: Bool) -> Bool {
    isSuccess && !isAvailable
}

func shouldApplyWatchProvisioningRevision(_ incoming: UInt64?, latest: UInt64?) -> Bool {
    guard let incoming else { return latest == nil }
    return latest.map { incoming > $0 } ?? true
}

nonisolated enum WatchProvisioningReplyError: String {
    case invalidPayload = "invalid_payload"
    case saveFailed = "save_failed"
}

nonisolated struct TVProvisioningRequest: Equatable {
    private static let serverKey = "server"
    private static let apiKeyKey = "apiKey"
    private static let revisionKey = "revision"

    let server: URL
    let apiKey: String
    let revision: UInt64?

    init?(dictionary: [String: Any]) {
        guard let serverText = dictionary[Self.serverKey] as? String,
              let key = dictionary[Self.apiKeyKey] as? String else { return nil }

        let revision = (dictionary[Self.revisionKey] as? String).flatMap(UInt64.init)
        self.init(serverText: serverText, apiKey: key, revision: revision)
    }

    private init?(serverText: String, apiKey keyText: String, revision: UInt64? = nil) {
        guard let candidate = URL(string: serverText), let server = Self.validatedServer(candidate) else { return nil }
        guard let key = Self.validatedAPIKey(keyText) else { return nil }

        self.server = server
        apiKey = key
        self.revision = revision
    }

    static func payload(server: URL, apiKey: String, revision: UInt64? = nil) -> [String: String]? {
        guard let server = validatedServer(server), let apiKey = validatedAPIKey(apiKey) else { return nil }

        var payload = [
            serverKey: server.absoluteString,
            apiKeyKey: apiKey
        ]
        if let revision { payload[revisionKey] = String(revision) }
        return payload
    }

    private static func validatedAPIKey(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUnsafeScalar = value.unicodeScalars.contains {
            let category = $0.properties.generalCategory
            return category == .control || category == .format
        }
        return value.isEmpty || value.utf8.count > 4096 || hasUnsafeScalar ? nil : value
    }

    private static func validatedServer(_ server: URL) -> URL? {
        guard server.scheme?.lowercased() == "https", server.host != nil,
              server.user == nil, server.password == nil, server.query == nil,
              server.fragment == nil else { return nil }
        return server
    }
}

#if os(iOS)
    extension TVProvisioningRequest {
        static func payload(for account: Account, revision: UInt64? = nil) -> [String: String]? {
            guard !account.isMock else { return nil }
            guard !account.hasMalformedBaseURLOverride else { return nil }

            return payload(server: account.resolvedBaseURL, apiKey: account.apiKey, revision: revision)
        }
    }
#endif
